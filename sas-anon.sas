%macro gruppen_anonymisieren(
	gruppen=,
	inputDaten = inputDaten,
	inputVariable = Wert,
	outputDaten = outputDaten,
	outputVariableBasis = Wert,
	ebenen = quartier*kreis,
	funktion = min,
	minWert = 1,
	maxWert = 3
);

	%LET inputLib = %SYSFUNC(SCAN(WORK.&inputDaten., -2));
	%LET inputDS = %SYSFUNC(SCAN(WORK.&inputDaten., -1));
	%PUT &=inputDaten &=inputLib &=inputDS;

	%LET gruppenSql = %SYSFUNC(translate(%QUOTE(&gruppen), ", ", "*"));
	%LET nGrpVar = %SYSFUNC(COUNTW(&gruppen, "*"));
	%PUT &=gruppen &=gruppenSql &=nGrpVar;

	%DO iVar = 1 %TO &nGrpVar;
		%LET _grpVar&iVar = %SYSFUNC(SCAN(&gruppen, &iVar, "*"));
	%END;
	%PUT &=_grpVar1;

	/* A) Existenz und Typ der Gruppierungs-Variablen klären */ 
	%macro existenz();
				PROC SQL NOPRINT;
					CREATE TABLE check AS
					SELECT NAME, TYPE
					FROM SASHELP.VCOLUMN
					WHERE UPCASE(LIBNAME) = UPCASE("&inputLib") 
					AND UPCASE(MEMNAME) = UPCASE("&inputDS")
					AND UPCASE(NAME) IN (
			%DO iVar = 1 %TO &nGrpVar;
				"%UPCASE(&&_grpVar&iVar.)",
			%END;
					"")
			;
				QUIT;
	%mend existenz;
	%existenz();

	PROC SQL NOPRINT;
		SELECT COUNT(*) INTO :anzGefunden
		FROM check;
	QUIT;

	%PUT *** &=nGrpVar &=anzGefunden;
	%IF &nGrpVar ^= &anzGefunden %THEN %DO;
		%PUT ERROR: Ich finde nicht alle Gruppierungs-Variablen;
	%END;


	/* B) Gruppen-Ausprägungen bestimmen */
	PROC SQL;
		CREATE TABLE gruppen AS
		SELECT DISTINCT &gruppenSql
		FROM &inputDaten;

	/* C) Makro-Variablen für Gruppen-Auswahl erstellen */
		SELECT Name, Type INTO :_grpVar1-:_grpVar99, :_grpTyp1-:_grpTyp99
		FROM check;
	QUIT;


	/* D) Filter-Variable erstellen */
	DATA gruppen;
		SET gruppen;

		filter = "WHERE " 
%DO iVar = 1 %TO &nGrpVar;
	%IF &&_grpTyp&iVar = char %THEN %DO;
			|| "&&_grpVar&iVar = '" || STRIP(&&_grpVar&iVar) || "' AND "
	%END;
	%ELSE %DO;
			|| "&&_grpVar&iVar = " || STRIP(&&_grpVar&iVar) || " AND "
	%END;
%END;
		|| "1";
;
	RUN;


	/* E) Makro Anonymisierung für jede Gruppe aufrufen */
	DATA _NULL_;
		SET gruppen;

		PRC = '%NRSTR(%gruppe_anonymisieren(id=' || _N_ || ', filter=' || strip(filter) || '));';
		CALL EXECUTE(PRC);
	RUN;


%mend gruppen_anonymisieren;





%MACRO gruppe_anonymisieren(id=, filter=);
	%PUT &=filter;

	PROC SQL NOPRINT;
		CREATE TABLE __teil AS
		SELECT *
		FROM &inputDaten
		&filter;
	QUIT;

	%anon_aggregatdaten(
		inputDaten = __teil,
		inputVariable = &inputVariable,
		outputDaten = __teil_out,
		outputVariableBasis = &outputVariableBasis,
		ebenen = &ebenen,
		funktion = &funktion,
		minWert = &minWert,
		maxWert = &maxWert
	);

	%IF &id = 1 %THEN %DO;
		DATA &outputDaten.;
			SET __teil_out;
		RUN;
	%END;
	%ELSE %DO;
		PROC APPEND DATA=__teil_out BASE=&outputDaten;
		RUN;
	%END;

%MEND gruppe_anonymisieren;



%macro anon_aggregatdaten(
	inputDaten = inputDaten,
	inputVariable = Wert,
	outputDaten = outputDaten,
	outputVariableBasis = Wert,
	ebenen = quartier*kreis,
	funktion = min,
	minWert = 1,
	maxWert = 3
);



	%LET ebenen = Nuller*&ebenen.*Einer;

	%MACRO vorbereitung(ebenen);
		
		%GLOBAL nEbenen;
		%LET nEbenen = %EVAL(%SYSFUNC(COUNTW(&ebenen., "*")) - 1);

		%DO iEbene = 0 %TO %EVAL(&nEbenen);
			%GLOBAL ebene_&iEbene;
			%LET ebene_&iEbene = %SCAN(&ebenen, %EVAL(&iEbene+1), "*");
		%END;

		DATA &outputDaten.;
			SET &inputDaten.;
			
			ID = _N_;
			Nuller = 0;
			Einer = 1;
		RUN;

	%MEND vorbereitung;

	%vorbereitung(ebenen = &ebenen.);



	/* Konsistenzprüfung */

	%MACRO inkonsistenz(RegOben=, RegUnten=, Gruppe=);
		%PUT ERROR: Inkonsistenz zwischen den Ebenen «&RegOben.» und «&RegUnten.» (&RegOben. &Gruppe.);
	%MEND inkonsistenz;


	%MACRO konsistenz();
		%DO iEbene = 1 %TO %EVAL(&nEbenen - 1);

			%LET iEbeneOben = %EVAL(&iEbene + 1);
			%LET iEbeneNochDarunter = %EVAL(&iEbene - 1);

			%LET ebOben = &&ebene_&iEbeneOben;
			%LET ebUnten = &&ebene_&iEbene;
			%LET ebNochDarunter = &&ebene_&iEbeneNochDarunter;


			PROC SQL NOPRINT;
				/* Werte auf der oberen Ebene */
				CREATE TABLE __kons_&iEbene._oben AS
				SELECT &ebOben., &inputVariable. 
				FROM &outputDaten.
				WHERE &ebOben ^= 0 AND &ebUnten = 0;

				/* Summen auf der unteren Ebene */
				CREATE TABLE __kons_&iEbene._unten AS
				SELECT &ebOben., SUM(&inputVariable.) AS summe
				FROM &outputDaten.
				WHERE &ebOben ^= 0 AND &ebUnten ^= 0 AND &ebNochDarunter = 0
				GROUP BY &ebOben.;

				/* Zusammenführen */
				CREATE TABLE __kons_&iEbene. AS
				SELECT oben.*, unten.Summe, oben.&inputVariable. - unten.Summe AS abw
				FROM __kons_&iEbene._oben AS oben
				LEFT JOIN __kons_&iEbene._unten AS unten
				ON oben.&ebOben. = unten.&ebOben.;
			QUIT;

			DATA _NULL_;
				SET __kons_&iEbene.;
				PUT _ALL_;
				IF abw ^= 0 THEN DO;
					CALL EXECUTE('%NRSTR(%inkonsistenz(RegOben=&ebOben, RegUnten=&ebUnten, Gruppe=' || &ebOben || '))');
				END;
			RUN;

			/* Aufräumen */
			PROC DATASETS LIBRARY=WORK NOLIST;
				DELETE TABLE __kons_&iEbene._oben __kons_&iEbene._unten __kons_&iEbene.;
			RUN;

		%END;
	%MEND konsistenz; 
	%konsistenz();



	/* 1 Primäre Anonymisierung */

	DATA &outputDaten.;
		SET &outputDaten.;
		LENGTH &outputVariableBasis._korr $11 &outputVariableBasis._fallLang $100;
		&outputVariableBasis._korr = LEFT(PUT(&inputVariable., best9.));
		IF &outputVariableBasis._korr >= &minWert. AND &inputVariable. <= &maxWert. AND &ebene_1 ^= 0 THEN DO;
			&outputVariableBasis._korr = "&minWert.–&maxWert.";
			&outputVariableBasis._min = &minWert.;
			&outputVariableBasis._max = &maxWert.;
			&outputVariableBasis._fall = "primär";
			&outputVariableBasis._fallLang = "Kleine Werte werden auf der untersten Ebene maskiert";
		END;
	RUN;




	/* 2 Sekundäre Anonymisierung */

	%MACRO sek_ersetzen(RegOben=, summe=, summe_untergrenze=, summe_obergrenze=, pri_anz=, pri_sum=, sek_anz=, sek_Unten=);
		
		%PUT &=RegOben, &=summe, &=pri_anz, &=pri_sum, &=sek_anz, &=sek_Unten;


		/* Einheiten Oben, in der Unten genau eine Einheit anonymisiert wurde */
		%IF %EVAL(&pri_anz = 1) %THEN %DO;

			/* Falls eine andere Einheit unten angepasst werden kann -> Fall A11, A21 etc. */
			%IF %EVAL(&sek_anz > 0) %THEN %DO;
				%PUT Fall A11, A21 etc.;

				PROC SQL noprint;
					SELECT &inputVariable. INTO :totalA
					FROM &outputDaten.
					WHERE &ebOben. = &RegOben. AND &ebUnten. = 0;

					SELECT SUM(&inputVariable.) INTO :summeNichtAnonA
					FROM &outputDaten.
					WHERE &ebOben. = &RegOben. AND &ebUnten. ^= 0 AND &ebNochDarunter = 0 AND &outputVariableBasis._fall = "" AND &ebUnten. ^= &sek_Unten;

					SELECT SUM(&outputVariableBasis._min), SUM(&outputVariableBasis._max) INTO :summeAnonMinA, :summeAnonMaxA
					FROM &outputDaten.
					WHERE &ebOben. = &RegOben. AND &ebUnten. ^= 0 AND &ebNochDarunter = 0 AND &outputVariableBasis._fall ^= "";
				QUIT;

				DATA _NULL_;
					totalA = SYMGET('totalA');
					summeNichtAnonA = SYMGET('summeNichtAnonA');
					summeNichtAnonA = SYMGET('summeNichtAnonA');
					summeAnonMinA = SYMGET('summeAnonMinA');
					summeAnonMaxA = SYMGET('summeAnonMaxA');
					PUT _ALL_;
				RUN;

				DATA &outputDaten.;
					SET &outputDaten.;
					IF &ebOben = &RegOben AND &ebUnten = &sek_Unten AND &ebNochDarunter = 0 THEN DO;
						&outputVariableBasis._min = SUM(SYMGET("totalA"), (-1)*SYMGET("summeNichtAnonA"), (-1)*SYMGET("summeAnonMaxA"));
						&outputVariableBasis._max = SUM(SYMGET("totalA"), (-1)*SYMGET("summeNichtAnonA"), (-1)*SYMGET("summeAnonMinA"));
						&outputVariableBasis._korr = STRIP(&outputVariableBasis._min) || "-" || STRIP(&outputVariableBasis._max);
						&outputVariableBasis._fall = "A&iEbene.1";
						&outputVariableBasis._fallLang = "Anonymisiert, damit in &ebUnten. &sek_Unten. keine Rückschlüsse gezogen werden können.";
					END;
				RUN;


			%END;

			/* Falls *kein* anderes Quartier angepasst werden kann -> Fall A12, A22 etc. */
			%ELSE %DO;
				%PUT Fall A12, A22 etc.;
				DATA &outputDaten.;
					SET &outputDaten.;
					IF &ebOben. = &RegOben. AND &ebUnten. = 0 THEN DO;
						&outputVariableBasis._korr = "&minWert.-&maxWert.";
						&outputVariableBasis._min = &minWert.;
						&outputVariableBasis._max = &maxWert.;
						&outputVariableBasis._fall = "A&iEbene.2";
						&outputVariableBasis._fallLang = "Anonymisiert, damit in &ebOben. &RegOben. keine Rückschlüsse gezogen werden können.";
					END;
				RUN;
			%END;
		%END;


		/* "Einheiten oben" mit mehr als einer anonymisierten Einheit unten */
		%IF %EVAL(&pri_anz > 1) %THEN %DO;
			%PUT Fall B;
			%PUT &=pri_sum &=summe_untergrenze &=summe_obergrenze;

			/* Falls der Wert der anonymisierten Einheiten unten alle der Untergrenze oder alle der Obergrenze des Intervalls entsprechen */
			%IF %EVAL(&pri_sum = &summe_untergrenze) OR %EVAL(&pri_sum = &summe_obergrenze) %THEN %DO;

				/* Falls eine andere Einheit Unten angepasst werden kann -> Fall B11, B21 etc. */
				%IF %EVAL(&sek_anz > 0) %THEN %DO;
					%PUT Fall B11, B21 etc.;
					PROC SQL noprint;
						SELECT &inputVariable. INTO :totalB
						FROM &outputDaten.
						WHERE &ebOben. = &RegOben. AND &ebUnten. = 0;

						SELECT SUM(&inputVariable.) INTO :summeNichtAnonB
						FROM &outputDaten.
						WHERE &ebOben. = &RegOben. AND &ebUnten. ^= 0 AND &ebNochDarunter = 0 AND &outputVariableBasis._fall = "" AND &ebUnten. ^= &sek_Unten;

						SELECT SUM(&outputVariableBasis._min), SUM(&outputVariableBasis._max) INTO :summeAnonMinB, :summeAnonMaxB
						FROM &outputDaten.
						WHERE &ebOben. = &RegOben. AND &ebUnten. ^= 0 AND &ebNochDarunter = 0 AND &outputVariableBasis._fall ^= "";
					QUIT;

					DATA &outputDaten.;
						SET &outputDaten.;
						IF &ebOben. = &RegOben. AND &ebUnten. = &sek_Unten AND &ebNochDarunter = 0 THEN DO;
							&outputVariableBasis._min = MAX(1, SUM(SYMGET("totalB"), (-1)*SYMGET("summeNichtAnonB"), (-1)*SYMGET("summeAnonMaxB")));
							&outputVariableBasis._max = SUM(SYMGET("totalB"), (-1)*SYMGET("summeNichtAnonB"), (-1)*SYMGET("summeAnonMinB"));
							&outputVariableBasis._fall = "B&iEbene.1";
							&outputVariableBasis._fallLang = "Anonymisiert, damit in &ebOben. &RegOben. keine Rückschlüsse gezogen werden können.";
						END;
					RUN;
					DATA &outputDaten.;
						SET &outputDaten.;
						IF &ebOben. = &RegOben. AND &ebUnten. = &sek_Unten AND &ebNochDarunter = 0 THEN DO;
							&outputVariableBasis._korr = STRIP(&outputVariableBasis._min) || "-" || STRIP(&outputVariableBasis._max);
						END;
					RUN;
				%END;

				/* Falls *kein* anderes Quartier angepasst werden kann -> Fall B12, B22 etc. */
				%ELSE %DO;
					%PUT Fall B12, B22 etc.;
					DATA &outputDaten.;
						SET &outputDaten.;
						IF &ebOben. = &RegOben. AND &ebUnten. = 0 THEN DO;
							&outputVariableBasis._min = &summe_untergrenze;
							&outputVariableBasis._max = &summe_obergrenze;
							&outputVariableBasis._korr = "&summe_untergrenze.-&summe_obergrenze.";
							&outputVariableBasis._fall = "B&iEbene.2";
							&outputVariableBasis._fallLang = "Anonymisiert, damit in &ebOben. &RegOben. keine Rückschlüsse gezogen werden können.";
						END;
					RUN;
				%END;
			%END;
		%END;

	%MEND sek_ersetzen;


	%macro sekundaer();
		
		/* Für jeweils zwei Ebenen, von unten kommend -- Start */
		%DO iEbene = 1 %TO %EVAL(&nEbenen - 1);
			%LET iEbeneOben = %EVAL(&iEbene + 1);
			%LET iEbeneNochDarunter = %EVAL(&iEbene - 1);

			%LET ebOben = &&ebene_&iEbeneOben;
			%LET ebUnten = &&ebene_&iEbene;
			%LET ebNochDarunter = &&ebene_&iEbeneNochDarunter;

			/* 2.1 Berechnungen */
			PROC SQL noprint;
				/* Pro "Einheit Oben": Totale */
				CREATE TABLE __sek_&iEbene._block0 AS
				SELECT &ebOben, SUM(&inputVariable.) AS summe
				FROM &outputDaten. 
				WHERE &ebUnten. ^= 0 AND &ebNochDarunter = 0
				GROUP BY &ebOben;

				/* Pro "Einheit Oben": Bereits anonymisierte "Einheiten Unten": Anzahl, Summe(&inputVariable.), Summe(Untergrenze) und Summe(Obergrenze) */
				CREATE TABLE __sek_&iEbene._block1 AS
				SELECT &ebOben, COUNT(*) AS anzahl, SUM(&inputVariable.) AS summe, SUM(&outputVariableBasis._min) AS summe_untergrenze, SUM(&outputVariableBasis._max) AS summe_obergrenze
				FROM &outputDaten. 
				WHERE &outputVariableBasis._fall ^= "" AND &ebUnten. ^= 0 AND &ebNochDarunter = 0
				GROUP BY &ebOben;

				/* Pro "Einheit Oben": Anzahl "Einheiten Unten" für nächste Anonymisierung */
				CREATE TABLE __sek_&iEbene._block2 AS
				SELECT &ebOben, COUNT(*) AS anzahl
				FROM &outputDaten.
				WHERE &inputVariable. > &maxWert. AND &ebUnten. ^= 0 AND &ebNochDarunter = 0
				GROUP BY &ebOben;

				/* Pro "Einheit Oben": Beste "Einheiten Unten" für nächste Anonymisierung */
				CREATE TABLE __sek_&iEbene._block3_a AS
				SELECT &ebOben, &ebUnten.
				FROM &outputDaten.
				WHERE &inputVariable. > &maxWert. AND &ebUnten. ^= 0 AND &ebNochDarunter = 0
				GROUP BY &ebOben
				HAVING &inputVariable. = &funktion.(&inputVariable.);

				CREATE TABLE __sek_&iEbene._block3 AS
				SELECT &ebOben, &ebUnten.
				FROM __sek_&iEbene._block3_a
				GROUP BY &ebOben.
				HAVING &ebUnten. = &funktion.(&ebUnten.);


				/* alles zusammenbauen */
				CREATE TABLE __sek_&iEbene._anon_1 AS
				SELECT b0.&ebOben, b0.summe AS summe, b1.anzahl AS pri_anz, b1.summe AS pri_sum, b1.summe_untergrenze, b1.summe_obergrenze, b2.anzahl AS sek_anz, b3.&ebUnten. AS sek_&ebUnten.
				FROM __sek_&iEbene._block0 AS b0
				LEFT JOIN __sek_&iEbene._block1 AS b1 ON b0.&ebOben=b1.&ebOben
				LEFT JOIN __sek_&iEbene._block2 AS b2 ON b0.&ebOben=b2.&ebOben
				LEFT JOIN __sek_&iEbene._block3 AS b3 ON b0.&ebOben=b3.&ebOben
				;
			QUIT;

			
			/* 2.2 Makro für jede Einheit auf der oberen Ebene aufrufen */
			DATA _NULL_;
				SET __sek_&iEbene._anon_1;
				IF pri_anz > 0 THEN DO;
					put _all_;
					call execute('%NRSTR(%sek_ersetzen(RegOben=' || &ebOben ||', summe=' || summe || ', summe_untergrenze=' || summe_untergrenze || ', summe_obergrenze=' || summe_obergrenze || ', pri_anz=' || pri_anz ||', pri_sum=' || pri_sum || ', sek_anz=' || sek_anz || ', sek_Unten=' || sek_&ebUnten. ||'))');
				END;
			RUN;


			/* 2.3 Aufräumen */
			PROC DATASETS LIBRARY=WORK NOLIST;
				DELETE __sek_&iEbene._block: __sek_&iEbene._anon_1;
			RUN;

		/* Für jeweils zwei Ebenen, von unten kommend -- Ende */
		%END;

	%mend sekundaer;

	%sekundaer();






	/* 3 Tertiäre Anonymisierung */


	%MACRO ter_ersetzen(RegOben=, RegUnten=, nachOben=, nachUnten=);

		DATA &outputDaten.;
			SET &outputDaten.;
			IF &ebOben. = &RegOben. AND &ebUnten. = &RegUnten AND &ebNochDarunter = 0 THEN DO; 
				&outputVariableBasis._min = SUM(&inputVariable., (-1)*SYMGET("nachUnten"));
				&outputVariableBasis._max = SUM(&inputVariable., SYMGET("nachOben"));
				&outputVariableBasis._korr = STRIP(&outputVariableBasis._min) || "-" || STRIP(&outputVariableBasis._max);
				&outputVariableBasis._fall = "C&iEbene.";
				&outputVariableBasis._fallLang = "Anonymisiert, damit in &ebOben. &RegOben. keine Rückschlüsse gezogen werden können.";
			END;
		RUN;

	%MEND ter_ersetzen;


	%macro tertiaer();
		
		/* Für jeweils zwei Ebenen, von oben kommend -- Start */
		%DO iEbene = %EVAL(&nEbenen - 2) %TO 1 %BY -1;

			%LET iEbeneOben = %EVAL(&iEbene + 1);
			%LET iEbeneNochDarunter = %EVAL(&iEbene - 1);

			%LET ebOben = &&ebene_&iEbeneOben;
			%LET ebUnten = &&ebene_&iEbene;
			%LET ebNochDarunter = &&ebene_&iEbeneNochDarunter;
			%PUT &=ebOben &=ebUnten &=ebNochDarunter;


			/* 3.1 Berechnungen */
			PROC SQL;

				/* Für jede mit [A%1, B%1 oder C%] anonymisierte "Einheit Oben" die Abweichungen nach unten und oben bestimmen */
				CREATE TABLE __ter_&iEbene._block1 AS
				SELECT &ebOben., &inputVariable.-&outputVariableBasis._min AS abw_unten, &outputVariableBasis._max-&inputVariable. AS abw_oben
				FROM &outputDaten. 
				WHERE &ebUnten. = 0 AND &ebOben. ^= 0 AND (&outputVariableBasis._fall LIKE "A%1" OR &outputVariableBasis._fall LIKE "B%1" OR &outputVariableBasis._fall LIKE "C%");

				/* Für jede "Einheit Oben" die zu anonymisierende "Einheit unten" bestimmen */
				CREATE TABLE __ter_&iEbene._block2 AS
				SELECT &ebOben., &ebUnten.
				FROM &outputDaten.
				WHERE &inputVariable. > 3 AND &ebUnten. ^= 0 AND &ebNochDarunter = 0 
				GROUP BY &ebOben.
				HAVING &inputVariable. = &funktion.(&inputVariable.);


				/* alles zusammenbauen */
				CREATE TABLE __ter_&iEbene._anon_1 AS
				SELECT b1.*, b2.&ebUnten.
				FROM __ter_&iEbene._block1 AS b1
				LEFT JOIN __ter_&iEbene._block2 AS b2 ON b1.&ebOben.=b2.&ebOben.
				;
			QUIT;
			
			/* 3.2 Hilfs-Makro für jede Einheit auf der oberen Ebene aufrufen */
			DATA _NULL_;
				SET __ter_&iEbene._anon_1;
				PUT _ALL_;
				CALL EXECUTE('%NRSTR(%ter_ersetzen(RegOben=' || &ebOben || ', RegUnten=' || &ebUnten || ', nachOben=' || abw_oben || ', nachUnten=' || abw_unten || '))');
			RUN;


			/* 3.3 Aufräumen */
			PROC DATASETS LIBRARY=WORK NOLIST;
				DELETE __ter_&iEbene._block: __ter_&iEbene._anon_1;
			RUN;

		/* Für jeweils zwei Ebenen, von oben kommend -- Ende */
		%END;

	%mend tertiaer;

	%tertiaer();





	/* 4 Aufräumen */

	DATA &outputDaten.;
		SET &outputDaten.;
		DROP ID Nuller Einer;
	RUN;

%MEND anon_aggregatdaten;

