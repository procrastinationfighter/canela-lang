Interpreter języka Canela
Autor: Adam Boguszewski, ab417730

Interpreter uruchamia się zgodnie z instrukcją z Moodle - należy użyć komendy `make` do skompilowania, a następnie użyć polecenia `./Interpreter program` gdzie `program` to ścieżka z plikiem źródłowym programu do interpretacji. 
Podkatalog `good` zawiera przykłady poprawnych programów. Zgodnie z prośbą, nazwy testów zaczynają się od numerów punktów, które spełniają. 
Podkatalog `bad` zawiera przykłady niepoprawnych programów. 
Podkatalog `old` zawiera kilka prostszych testów, o mniejszej wartości demonstracyjnej i można je zignorować.
Testy, który nie zaczynają się od numerów, pokazują zachowania niewspomniane w treści.

Pliki wygenerowane automatycznie: ParCanela.hs LexCanela.hs
Pliki wygenerowane i zmodyfikowane: AbsCanela.hs CanelaInterpreter.hs
Plik Main.hs został stworzony na podstawie automatycznie wygenerowanego pliku TestCanela.hs

Gramatyka języka uległa nieznacznym zmianom: usunięto nawiasy wokół warunku pętli while, lambdy wymagają podania typu zwracanego, można deklarować funkcje i enumy wewnątrz funkcji.

Wszystkie planowane funkcjonalności zostały zrealizowane:

  01 (trzy typy)
  02 (literały, arytmetyka, porównania)
  03 (zmienne, przypisanie)
  04 (print)
  05 (while, if)
  06 (funkcje lub procedury, rekurencja)
  08 (zmienne read-only i pętla for)
  09 (przesłanianie i statyczne wiązanie)
  10 (obsługa błędów wykonania)
  11 (funkcje zwracające wartość)
  13 (2) (funkcje zagnieżdżone ze statycznym wiązaniem)
  17 (4) (funkcje wyższego rzędu, anonimowe, domknięcia)

  N1 (2-4) (rekurencyjne typy algebraiczne)
  N2 (1-2) (jednopoziomowy pattern matching)

Razem: 29 punktów lub więcej

