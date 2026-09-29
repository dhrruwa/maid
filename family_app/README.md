# Family (cook_family)

The app for the household's family members: see the menu for the next 7 days
and book the meals you will eat, so the cook knows how many to cook for.

- Log in once with your name and a 4-digit PIN (the last 4 digits of your
  phone number, set by the owner in the Owner app → Settings → Family members).
  The phone remembers the login until you log out or the owner resets it.
- Edge Functions used: `member_login`, `member_home`, `book_meal`.

Build (keys come from the git-ignored `../dart_defines.json`):

    flutter build apk --release --dart-define-from-file=../dart_defines.json
    flutter build ios --release --dart-define-from-file=../dart_defines.json

Icon artwork: `../branding/family.svg` (built by `../branding/family-build.js`,
then `dart run flutter_launcher_icons`).

UI tests on a simulator / phone (screenshots go to `SCREENSHOT_DIR`):

    # Against the live project, as a THROWAWAY member the owner created for
    # testing (name must start with "Test "). Books, notes and cancels one meal.
    SCREENSHOT_DIR=/tmp/family-shots flutter drive -d <device> \
      --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
      --dart-define-from-file=../dart_defines.json \
      --dart-define=TEST_NAME='Test …' --dart-define=TEST_PIN=<4 digits>

    # Layout / error paths against a fake server inside the test (no real data).
    SCREENSHOT_DIR=/tmp/family-shots flutter drive -d <device> \
      --driver=test_driver/integration_test.dart --target=integration_test/layout_test.dart \
      --dart-define=SUPABASE_URL=http://127.0.0.1:47651 --dart-define=SUPABASE_ANON_KEY=fake-key-for-tests

`flutter drive` uninstalls the app when it finishes; add `--keep-app-running`
to keep it (and its login) installed.
