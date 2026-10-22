# Tests

Run all tests from anywhere in the repository:

```
tests/run.sh
```

Run some of them, with their paths relative to the repository root:

```
tests/run.sh tests/test_make_dashboards_layout.py
```

Each test is a standalone Python 3 script with plain `assert`s; it exits
non-zero when a check fails. A test changes to the repository root before
importing the module it tests, so it also runs directly:

```
python3 tests/test_make_dashboards_layout.py
```

## Adding a test

- Name it `tests/test_<what it tests>.py`; `run.sh` picks it up.
- Start it the way the existing tests do, so it imports from the repository
  root and reads files relative to it:

  ```python
  ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
  os.chdir(ROOT)
  sys.path.insert(0, ROOT)
  ```

- Put the data it reads in `tests/data/<test name>/`.
