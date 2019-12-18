# Anonymisierung von Aggregatdaten

## Motivation
In hierarchischen Klassifikationen reicht es nicht aus, die Angaben auf der tiefsten Ebene zu maskieren. Vielmehr muss über alle Hierarchiestufen sichergestellt werden, dass Rückschlüsse auf maskierte Werte möglich sind. Dieses Vorgehen ist mühselig und -- wenn es von Hand ausgeführt wird -- fehleranfällig. Der hier publizierte SAS-Code erledigt diese Arbeit rasch und zuverlässig. 
 
## Vorgehen
Das Vorgehen umfasst drei Stufen: 
 - in der primären Anonymisierung werden kleine Werte auf der tiefsten Hierarchie-Ebene maskiert. Mittels Parametern kann angegeben werden, welche Werte maskiert werden sollen.
- in der sekundären Anonymisierung wird die Maskierung "mit Blick nach oben" gesichert: Falls von einem Wert auf einer höheren Hierarchiestufe Rückschlüsse auf einen maskierten Wert gezogen werden können, wird ein weiterer Wert auf der unteren Hierarchiestufe oder (falls dies nicht möglich ist) der Wert auf der oberen Hierarchiestufe maskiert.
- in der tertiären Anonymisierung wird die Maskierung "mit Blick nach unten" gesichert: Falls von einem Wert auf einer tieferen Hierarchiestufe Rückschlüsse auf einen maskierten Wert gezogen werden können, wird ein weiterer Wert auf der unteren Hierarchiestufe oder (falls dies nicht möglich ist) der Wert auf der oberen Hierarchiestufe maskiert.

## Grundsätze
Die Anonymisierung verfolgt die folgenden Grundsätze
- Es wird so viel wie nötig und so wenig wie möglich anonymisiert
- Je höher die Hierarchiestufe, desto wertvoller die Information: Die Anonymisierung erfolgt möglichst "weit unten", sodass Informationen auf einer höheren Ebene möglichst unverändert publiziert werden können.

## Der Algorithmus
Der Algorithmus ist in SAS geschrieben, das Vorgehen kann aber problemlos auch in anderen Programmiersprachen umgesetzt werden. Auf Grund der Parametrisierung kann er auf beliebige Hierarchien angewendet werden (siehe "Anwendung").

## Beispiel
### Inputs
Der folgende Code erzeugt die Daten
```sas
data have;
   input Kreis Quartier Wert;
   datalines;
0 0 28
1 0 9
1 1 2
1 2 7
2 0 2
2 1 2
2 2 0
3 0 17
3 1 17
;
```

| Kreis | Quartier | Wert |
| ------ | ------ | --|
| 0 | 0 | 28 |
| 1 | 0 | 9 |
| 1 | 1 | 2 |
| 1 | 2 | 7 |
| 2 | 0 | 2 |
| 2 | 1 | 2 |
| 2 | 2 | 0 |
| 3 | 0 | 17 |
| 3 | 1 | 17 |



### Outputs

Der folgende Code anonymisiert die oben erzeugten Daten.
```sas
%anon_aggregatdaten(
            inputDaten = have,
            inputVariable = Wert,
            outputDaten = outputDaten,
            outputVariableBasis = Wert,
            ebenen = Quartier*Kreis,
            funktion = max,
            minWert = 1,
            maxWert = 3
);
```

und liefert den folgenden Output:

| Kreis | Quartier | Wert | Wert_korr | Wert_fallLang | Wert_min | Wert_max | Wert_fall |
| ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ |
| 0 | 0 | 28 | 28 |  | . | . |  |
| 1 | 0 | 9 | 9 |  | . | . |  |
| 1 | 1 | 2 | 1–3 | Kleine Werte werden auf der untersten Ebene maskiert | 1 | 3 | primär |
| 1 | 2 | 7 | 6-8 | Anonymisiert, damit in Quartier 2 keine Rückschlüsse gezogen werden können. | 6 | 8 | A11 |
| 2 | 0 | 2 | 1-3 | Anonymisiert, damit in Kreis 2 keine Rückschlüsse gezogen werden können. | 1 | 3 | A12 |
| 2 | 1 | 2 | 1–3 | Kleine Werte werden auf der untersten Ebene maskiert | 1 | 3 | primär |
| 2 | 2 | 0 | 0 |  | . | . |  |
| 3 | 0 | 17 | 16-18 | Anonymisiert, damit in Kreis 3 keine Rückschlüsse gezogen werden können. | 16 | 18 | A21 |
| 3 | 1 | 17 | 16-18 | Anonymisiert, damit in Kreis 3 keine Rückschlüsse gezogen werden können. | 16 | 18 | C1 |

### Erläuterung
Die Spalten "Kreis" und "Quartier" zeigen die Hierarchien der Klassifikation.
