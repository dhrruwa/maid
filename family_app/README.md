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
