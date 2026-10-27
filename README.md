# os-practice-2

Практическая работа по ОС в Linux: bash-скрипт для анализа логов, Python-скрипт, работающий с файлом, и разбор системных вызовов (`strace`) для `python3` и `cat`.

## Содержимое

| Файл | Описание |
|------|----------|
| `report.sh` | Bash-скрипт: считает записи уровня `ERROR` или `WARN` по модулям в `*.log` файлах каталога |
| `hello.py` | Python-скрипт: читает `sample.txt` и выводит его имя и размер в байтах |
| `sample.txt` | Тестовый файл (39 байт) |
| `app.log` | Пример лог-файла для `report.sh` |
| `trace.txt` | Трассировка системных вызовов `python3 hello.py` (PID 7913) |
| `trace-cat.txt` | Трассировка системных вызовов `cat sample.txt` (PID 8069) |

## report.sh

Скрипт ищет во всех файлах `<directory>/*.log` строки, где среди слов встречается уровень (`ERROR` или `WARN`), берёт слово, следующее сразу за уровнем, как имя модуля и считает количество записей по каждому модулю.

### Использование

```bash
./report.sh <directory> <ERROR|WARN> [--top N]
```

| Аргумент | Описание |
|----------|----------|
| `<directory>` | Каталог с `.log` файлами (должен существовать) |
| `<ERROR\|WARN>` | Уровень логирования для подсчёта |
| `--top N` | Необязательно. Показать только N лучших модулей (N — положительное целое) |

### Примеры

```bash
chmod +x report.sh

# Все модули с ошибками в текущем каталоге
./report.sh . ERROR

# Топ-3 модуля по предупреждениям
./report.sh . WARN --top 3
```

### Формат вывода

```
Module                 Count
---------------------  -----
<module>               <число>
```

Сортировка: по убыванию количества, при равенстве — по имени модуля.

### Проверки и коды возврата

Скрипт завершается с кодом `1` и выводит подсказку по использованию, если:

- передано меньше двух аргументов;
- каталог не существует;
- уровень не `ERROR` и не `WARN`;
- третий и четвёртый аргументы заданы неверно (ожидается ровно `--top N`, где `N >= 1`).

## hello.py

Читает файл `sample.txt` в байтовом режиме и печатает:

```
File: sample.txt
Size: 39 bytes
```

При ошибке ввода-вывода (например, файл не найден) выводит `Error: ...` и завершается с кодом `1`.

```bash
python3 hello.py
```

Содержимое `sample.txt`:

```
Hello from Linux!
This is a test file.
```

## Анализ системных вызовов (strace)

Трассировки сняты в каталоге `/home/ademi/os-practice-2`, в окружении Python 3.14 (`/usr/bin/python3.14`) на x86_64 Linux.

### trace.txt — `python3 hello.py`

1. **Запуск:** `execve("/usr/bin/python3", ["python3", "hello.py"], ...)`.
2. **Загрузка библиотек:** динамический загрузчик читает `/etc/ld.so.cache` и подключает `libm.so.6`, `libz.so.1`, `libexpat.so.1`, `libc.so.6` (`openat` → `read` → `fstat` → `mmap` → `close`).
3. **Инициализация интерпретатора:** `arch_prctl`, `set_tid_address`, `rseq`, `mprotect`, `getrandom`; чтение `/proc/sys/vm/overcommit_memory`, настройка локали (`C.utf8`), часового пояса (`/etc/localtime` → `Asia/Bishkek`) и обработчиков сигналов (`rt_sigaction`).
4. **Поиск стандартной библиотеки:** серия `newfstatat` с `ENOENT` по путям `PATH` и `sys.path`, после чего находится `/usr/lib/python3.14`.
5. **Импорт модулей:** загружаются `.pyc` из `__pycache__` (`encodings`, `pathlib`, `re`, `enum`, `glob`, `functools` и др.).
6. **Чтение скрипта:** `openat("/home/ademi/os-practice-2/hello.py")`, размер 252 байта.
7. **Работа программы:** `openat("sample.txt")` → `read` (39 байт) → `close`.
8. **Вывод:** два `write(1, ...)` в терминал `/dev/pts/6` (`File: sample.txt`, `Size: 39 bytes`).
9. **Завершение:** `munmap` → `exit_group(0)`.

### trace-cat.txt — `cat sample.txt`

1. **Запуск:** `execve("/usr/bin/cat", ["cat", "sample.txt"], ...)`.
2. **Библиотеки:** `libselinux.so.1`, `libgcc_s.so.1`, `libm.so.6`, `libc.so.6`, `libpcre2-8.so.0`.
3. **Проверка SELinux:** `statfs("/sys/fs/selinux")`, чтение `/proc/filesystems` и `/proc/mounts`, проверка `/etc/selinux/config` (отсутствует).
4. **Локализация:** чтение `/usr/share/coreutils/locales/uucore/en-US.ftl`.
5. **Копирование файла:** `statx` и `openat("sample.txt")`, затем `splice` файл → терминал завершается `EINVAL`, и `cat` переключается на схему через канал: `pipe` → `splice(file → pipe)` (39 байт) → `splice(pipe → stdout)` (39 байт).
6. **Завершение:** `close` дескрипторов → `exit_group(0)`.

### Сравнение

| | `python3 hello.py` | `cat sample.txt` |
|---|---|---|
| Строк в трассе | значительно больше | значительно меньше |
| Основная нагрузка | инициализация интерпретатора, поиск и импорт модулей | загрузка библиотек и копирование данных |
| Чтение файла | `read` (39 байт) | `splice` через `pipe` |
| Вывод | два `write` | `splice` в stdout |
| Код возврата | 0 | 0 |

Вывод: для простой задачи «прочитать 39 байт» интерпретатору Python требуется на порядок больше системных вызовов, чем утилите `cat`, из-за запуска рантайма и импорта модулей.

## Как воспроизвести трассировки

```bash
strace -f -y -o trace.txt python3 hello.py
strace -f -y -o trace-cat.txt cat sample.txt
```
