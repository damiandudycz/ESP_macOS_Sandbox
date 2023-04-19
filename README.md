Na początku, w katalogu projektu, powinien być tylko katalog scripts.

Skrypty należy wykonywać z poziomu katalogu projektu, np.:
./scripts/setup-esp-idf-env.sh esp32s3 HelloWorld

Najważniejsze skrypty:

install-system-dependencies.sh
Instaluje zależności systemowe, potrzebne do skonfigurowania środowiska ESP-IDF.
Może zostać pominięty jeśli był już wcześniej wykonany w systemie.

setup-esp-idf-env.sh
Pobiera ESP-IDF i ESP-IDF-TOOLS do katalogu lokalnego env.

update-env-location.sh
Aktualizuje zmienne, które posiadają ścieżki globalne w katalogu env.
Powinien zostać wykonany po przeniesieniu projektu do innego katalogu.
W przypadku pracy w Xcode, zostanie wywołany podczas buildu projektu, więc można
pominąć jego ręczne wywołanie.

create-esp-idf-project.sh
Tworzy nowy projekt skonfigurowany korzystający z ESP-IDF i ESP-IDF tools.
Taki projekt może zostać skompilowany w terminalu przez idf.py, lub w VSCode
w rozszerzeniu Espressif IDF.

build.sh
Kompiluje projekt przy pomocy idf.py. Przed wykonaniem aktualizuje zmienne 
środowiskowe przy pomocy narzędzia env/esp-idf/export.sh

// ... Dodać więcej skryptów

Tworzenie projektu dla Xcode:
Projekt tworzy się skryptem setup-xcode.sh.
skrypt powinien:
 - być typu external build system
 - dodać zmienne środowiskowe IDF_PATH i IDF_TOOLS_PATH, które powinny być relatywne do $(SRCROOT)
 - korzystać ze skryptu scripts/build.sh
 - przekazywać $(PRODUCT_NAME) i $(ACTION) jako parametry
 - dodawać zmienne środowiskowe targetu do skryptów build
 - wywoływać scripts/update-env-location.sh przez buildem
Template projektu powinien zawierać katalogi env i scripts oraz katalog projektu
stworzonego przez create-esp-idf-project.sh. Katalogi mogą nie istnieć w 
template, zostaną powiązane po ich utworzeniu i aktualizacji projektu template.
Podczas tworzenia projektu, nazwa projektu oraz powiązany katalog powinny
zostać zaktualizowane do wartości odpowiadającej nazwie projektu.

Jeśli to możliwe to można dodać do projektu również targety, które pobierają env,
generują nowy projekt, itp. Wtedy będzie można rozpocząć pracę z projektu Xcode
i przygotować wszystko z niego.

Dodać opcję, która jeśli nie ma katalogu env wywoła w Xcode opcję instalację całego environment





Konfiguracja nowego projektu:

1. Pobrać archiwum template, powinno zawierać:
katalog scripts, nic więcej
wywołać po kolei skrypty:
scripts/install-system-dependencies.sh
scripts/setup-esp-idf-env.sh
scripts/create-xcode-project.sh

IDF_PATH i IDF_TOOLS_PATH można by było wpisać do zmiennych w projekcie Xcode,
ale skoro Xcode i tak korzysta ze skryptów, które również exportują te zmienne,
nie ma takiej potrzeby. Dodać gdyby okazało się to przydatne.
