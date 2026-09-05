# Task 3: identity, ownership and password recovery

This is a focused portfolio hardening change. Routes remain in `app/main.py`.

## Audit before changes

Both login routes checked passwords and returned profiles. They issued no credential.
The two old `Authorization: Bearer ...` snippets in Flutter's seller service were
unused/incomplete; the backend had no bearer validation. User restoration trusted
`user_email` and a public user list; seller restoration trusted cached `seller_data`.
Neither `Session.currentUser` nor `SellerSession` proved identity to the backend.

All POST/PUT/PATCH/DELETE route definitions and Flutter HTTP/multipart callers were
reviewed. There were no PATCH routes, and no existing mutations in categories A
(authenticated with ownership) or B (authenticated without ownership).
The original 49 mutation routes classified as A: 0, B: 0, C: 41, D: 8.

| Existing mutation routes | Before | After |
| --- | --- | --- |
| POST `/users`, `/sellers/signup`, `/users/login`, `/sellers/login` | D: public registration/login | Public; registration keeps phone verification, login issues credentials |
| POST `/send-verification-code`, `/verify-phone`, `/send-seller-verification-code`, `/verify-seller-phone` | D: public registration OTP | Public for registration; verifying an existing account also requires that actor |
| PUT/DELETE `/users/{user_id}`; POST `/users/{user_id}/send-phone-verification` | C: unauthenticated | User credential and self ownership; generic update rejects password fields |
| POST `/send-email-verification-code`, `/verify-email`, `/send-seller-email-verification-code`, `/verify-seller-email` | C | Correct role and own email |
| PUT `/sellers/profile` | C | Seller credential and self ownership; supplied ID must match |
| POST `/products`; PUT/DELETE `/products/{product_id}` | C | Seller credential; owner derived on create, checked on update/delete, no transfer |
| POST `/upload-image` | C | Seller credential |
| POST `/address`; PUT/DELETE `/address/{address_id}` | C | User credential; direct owner set on create and checked on mutations |
| POST `/tokenize`, `/charge`, `/credit_card`; PUT/DELETE `/credit_card/{card_id}` | C | User credential, own payment resource/token; tokenization binds token to actor |
| POST `/order`; PUT/DELETE `/order/{order_id}` | C | User owner; address/card must belong to actor; buyer cannot set fulfillment status |
| POST `/users_address`, `/users_credit_card`, `/users_order`; PUT/DELETE their `/{id}` routes | C | Both relationship and referenced resource ownership checked; supplied user must match |
| PUT `/seller_orders/{order_id}/status` | C | Only the seller exclusively fulfilling that order |
| POST `/seller_reviews`; PUT/DELETE `/seller_reviews/{review_id}` | C | User author; product/seller relationship checked on create |
| POST follow and DELETE unfollow under `/users/{user_id}` | C | Self ownership |
| POST `/sms/welcome`, `/sms/order-status`, `/sms/promotional` | C | Direct utilities disabled (401 without credentials, 403 with credentials); internal SMS workflows remain |

## Server credential and contracts

`app/auth.py` signs a small access credential with HMAC-SHA256. The format is
`base64url(JSON).base64url(signature)`, **not JWT**. Signed claims include account ID,
role (`user` or `seller`), one-hour expiration and a keyed password fingerprint.
Missing, tampered, expired or deleted-account credentials return 401; wrong account
type and other owners return 403. A password change/reset invalidates old access
credentials statelessly. No refresh token, reset token, blacklist or session service
was added. The existing PBKDF2 hashing and legacy password verification are retained.

Login responses keep their password-free profile fields and add `access_token` and
`token_type: bearer`. Use `Authorization: Bearer <access_token>` for private calls.
Missing `AUTH_SECRET_KEY` (or fewer than 32 bytes) fails closed with 503. Put a random
secret in the existing ignored `Backend/config.env`; see `config.env.example`.
Keep the same secret across backend workers/restarts. Changing it logs everyone out.

* GET/PUT `/users/me` uses the authenticated actor. The old PUT/DELETE ID routes
  remain checked for compatibility. Profile input has name/email/phone only and
  rejects extra fields. Contact changes cannot claim another user's registered phone.
* PUT `/users/me/password` requires `current_password`, `new_password` and
  `new_password_again`. Both new-password fields accept 8–1024 characters. Wrong
  current password returns 401; after that check, unequal new passwords return 400
  without changing the stored hash. Missing confirmation returns 422. Success hashes
  the new password, cancels outstanding reset challenges, and requires sign-in again.
* POST `/auth/forgot-password/request` takes `phone_number`. A unique matching user
  receives a fresh six-digit cryptographically generated SMS code. Phone formatting
  is normalized; unknown or ambiguous legacy numbers get the same generic response.
  Resends within 60 seconds do not replace the code or replenish attempts.
* POST `/auth/forgot-password/reset` takes `phone_number`, `verification_code`,
  `new_password`. A dedicated `password_reset_verifications` row binds the user and
  phone, stores an HMAC of the code, expires after five minutes and permits three
  failed attempts. Conditional database updates enforce the attempt limit and consume
  the challenge once in the same transaction as the password change. Registration,
  phone-change and historical verified flags cannot authorize this endpoint.
* GET/PUT `/sellers/profile` accepts an optional legacy `seller_id`; it must match
  the seller credential. The missing seller phone-resend route was added to match
  Flutter's existing caller. Existing-account phone verification updates only its owner.

Address/order owners are recorded before the client creates its relationship rows;
an orphan is never claimable by guessing its ID. Card tokenization records ownership
before returning a provider token. Saving a card requires that issued token, and card
updates cannot replace payment credentials. Card/address/order/relationship lists
are now limited to the authenticated user. Seller order/statistics views require the
matching seller. Mixed-seller legacy orders return 403 on status mutation because
status is stored for the entire order. Flutter checkout already splits new orders
by seller, so its normal workflow is preserved.

Product image cleanup also refuses paths outside its filename boundary and never
deletes an image still referenced by another product. Copying another seller's public
image URL into an owned product therefore does not grant deletion of that shared image.

Validation errors redact passwords, OTPs, access/payment tokens and card data.
No new secret logging was added; `main.py` remains free of print calls.

## Existing development database

New empty databases receive the models through the repository's existing
`create_all` startup. This **does not alter existing tables**. For an existing
PostgreSQL database, back it up, stop the backend and run:

```powershell
psql -d YOUR_DATABASE -f Backend/scripts/task3_authorization.sql
```

The migration adds nullable owner columns to `address` and `order`, the dedicated
reset table, and the follower counter already used by legacy SQL. It backfills only
unambiguous owners from existing links, including missing card owners. Review the
reported unowned IDs and inconsistent legacy links manually; the API refuses such
records instead of assigning them to the first caller. This migration is not a
retroactive proof that old client-supplied links were truthful. No live database is
modified by the automated tests. For disposable SQLite development databases, create
a fresh database with the new models; the checked-in SQL migration targets PostgreSQL.

## Flutter

`AuthSession` stores distinct user/seller access credentials in the existing
SharedPreferences setup. `AuthHttp` attaches the correct credential for API and
multipart requests, and clears the relevant session when the server rejects it.
An incorrect current password can be retried without discarding the credential.
Startup reloads credentials and asks the backend for the current profile; an email
or cached seller profile is insufficient. Old cached-only sessions must log in again.
Profile editing uses `/users/me`; the password section inside Account Information
uses the dedicated endpoint with current/new/confirmation fields. Forgot password
has a phone → SMS code → new password form and never
fetches profiles or asks for a full name/email as proof. Successful password changes
clear the local user credential and return the user to login.

## Intentional boundaries

* Login and public registration/SMS abuse controls are not a production rate-limiting
  service. Password reset has a resend cooldown and attempt limit, not global/IP limits.
* SharedPreferences is the project's existing local storage, not an OS secure vault.
  HTTPS/deployment configuration and client device compromise remain outside this patch.
* The public user directory, seller public profiles, diagnostic GET routes and legacy
  public data presentation have not undergone a complete read-only privacy audit.
* Payment pricing, actual checkout settlement, order quantities/state transitions,
  refund policy, file-upload validation and purchase-gated reviews need separate work.
  This patch checks actor/resource ownership, not payment business correctness.
* Registration OTP expiry/consumption rules and seller password recovery were not
  redesigned. Their codes cannot authorize the new user-password reset flow.
* No OAuth, MFA, refresh flow, router extraction, live SMS/payment call, commit or push.

## Verification

Run from the repository root:

```powershell
python -m pytest Backend/tests -q
python -m compileall -q Backend/app Backend/tests
flutter test --no-pub
flutter analyze --no-pub
git diff --check
```

Tests exercise the real API and signed credentials with disposable SQLite, mock
Twilio/email/payment boundaries, and test Flutter requests/screens with MockClient.
The PostgreSQL migration and a physical-device/live-provider flow still require
environment-specific verification. See `tests/README.md` for test dependencies.

Initial Task #3 verification: **61 backend tests passed**, **16 Flutter tests passed**,
Python compilation passed, and `git diff --check` passed. Flutter analysis reports
**0 errors, 30 warnings and 342 info diagnostics**; the pre-existing lint backlog
was not treated as part of this security patch. Backend tests also report datetime
and Pydantic deprecation warnings. External providers and the live PostgreSQL
database were not used. A generated signing secret was added only to the ignored
local `config.env`; its value is neither in this report nor in the Git diff.

## Changed files and diff summary

29 tracked/new source, test and documentation files are part of Task #3 and its follow-up:

| Area | Files |
| --- | --- |
| Backend identity and routes | `Backend/app/auth.py`, `Backend/app/main.py` |
| Models and contracts | `Backend/app/models.py`, `Backend/app/schemas.py` |
| Configuration and migration | `Backend/config.env.example`, `Backend/scripts/task3_authorization.sql` |
| Documentation | `Backend/AUTHORIZATION.md`, `Backend/tests/README.md` |
| Backend regression tests | `Backend/tests/conftest.py`, `Backend/tests/test_authorization.py`, `Backend/tests/test_password_confirmation.py`, `Backend/tests/test_password_responses.py`, `Backend/tests/test_sensitive_logging.py` |
| Flutter transport and sessions | `lib/Services/auth_http.dart`, `lib/Services/auth_session.dart`, `lib/Services/api_service.dart`, `lib/Services/seller_api_service.dart`, `lib/Models/seller_session.dart`, `lib/splash_screen.dart` |
| Flutter account flows | `lib/Pages/user/auth/login.dart`, `lib/Pages/user/auth/forgot_password.dart`, `lib/Pages/user/profile/account_info.dart`, `lib/Pages/user/profile/profile.dart`, `lib/Utils/language_manager.dart` |
| Seller uploads | `lib/Pages/seller/products_page.dart` |
| Flutter regression tests | `test/account_password_test.dart`, `test/authentication_test.dart`, `test/sensitive_logging_test.dart`, `test/user_response_compatibility_test.dart` |

The diff adds one small signing module, role/ownership checks on the existing routes,
self profile/password endpoints, isolated OTP recovery and its minimal DB support.
Flutter carries and validates real credentials and replaces profile-data password
recovery with the phone OTP form. Regression tests retain the earlier password-output
and sensitive-log checks. No routes were moved into routers and no commit was created.

## Focused follow-up after Task #3

### Backend confirmation and unchanged security

The required confirmation is documented in Pydantic/OpenAPI and included in the
existing sensitive-field validation redaction. Authentication and current-password
verification still run before the equality check. A mismatch changes neither the
stored password nor the validity of the existing access token. Success retains the
same hash, reset-challenge cleanup, transaction and token invalidation logic.

The only changed backend function is `change_password`; the only changed schema is
`PasswordChange`. Both forgot-password handlers and their schemas are unchanged.
Their six-digit OTP, purpose binding, expiry, attempts, resend cooldown and atomic
single-use behavior remain covered by the full regression suite. The auth module,
ownership checks, generic profile password exclusion and response/log protections
are retained. No database migration or configuration change is needed for this follow-up.

### Account Information and design review

Profile still opens Account Information. Below its existing personal-information
card and save action is a password card with current/new/confirmation inputs.
The separate profile menu item and unused standalone password page were removed.
All three fields start obscured and have independent visibility toggles. Local
validation rejects mismatches before HTTP; the backend enforces the same rule.

The section reuses Account Information's existing input-row builder: grey-filled
12px outlined fields, blue focus borders, 14px labels, 24px icons and the same row
spacing. Its card uses the existing 24px corners/padding, elevation and 22px blue
title. The full-width action matches the existing save button's 16px corners,
18px bold text and 20px loading spinner. During submission, account mutations and
inputs are disabled. Success clears all password controllers and the user session,
shows the shared `CustomDialog`, then opens login and clears the old navigation
stack. A wrong current password retains the session for retry.

Forgot-password phone, OTP and password inputs now use the surrounding user-login
form's filled-grey fields, blue icons/focus borders, 15px corners, typography and
spacing. Its white form card, 24px page margin and 50px primary buttons follow the
same screen. Field validation is shown inline; network/OTP errors use the existing
error dialog and requests use the established spinner/disabled-control pattern.
Only presentation changed; the recovery request bodies and validation rules remain
the same. The new-password visibility toggle follows the existing login convention.

Three existing Turkish password translations incorrectly contained English text;
those entries were corrected, and confirmation reuses the existing translation key.
The login/splash and seller changes from Task #3 were also reviewed: they changed
transport/session handling, not their widget styling. Seller styles were preserved.

Existing login and personal-information screens were visually compared with the
new password card, its validation state, and both recovery-form states using local
390×844 Flutter renders. The renders use the app's Material theme and Android's
Roboto fallback (Poppins is requested by existing styles but not bundled). This is
a widget render review, not a new physical-device or live-SMS smoke test.

### Follow-up files and checks

Relative to the already implemented Task #3 state, this follow-up modifies 12
files, adds two focused test files and removes one obsolete page:

| Change | Files |
| --- | --- |
| Confirmation and redaction | `Backend/app/main.py`, `Backend/app/schemas.py` |
| Updated backend regression requests | `Backend/tests/test_authorization.py`, `Backend/tests/test_password_responses.py`, `Backend/tests/test_sensitive_logging.py` |
| New backend cases | `Backend/tests/test_password_confirmation.py` |
| API caller | `lib/Services/api_service.dart` |
| Account integration/navigation | `lib/Pages/user/profile/account_info.dart`, `lib/Pages/user/profile/profile.dart` |
| Removed unused page | `lib/Pages/user/profile/change_password.dart` |
| Recovery styling and password labels | `lib/Pages/user/auth/forgot_password.dart`, `lib/Utils/language_manager.dart` |
| Flutter tests | Updated `test/authentication_test.dart`; added `test/account_password_test.dart` |
| Documentation | `Backend/AUTHORIZATION.md` |

Verification results:

* **68 backend tests passed**, including missing/malformed confirmation, mismatch
  without mutation, wrong current password, hashing, token invalidation and OTP
  regressions. There are 315 existing dependency/datetime deprecation warnings.
* **21 Flutter tests passed**, including the profile-to-account route, obscured
  fields/toggles, mismatch without HTTP, exact three-field body, disabled/loading
  states, cleared inputs/session, success-to-login navigation and existing profile
  editing, login/session, seller and OTP behavior.
* Python compilation and `git diff --check` passed.
* `flutter analyze --no-pub`: **0 errors, 30 warnings, 336 info diagnostics**.
  It exits nonzero for the remaining lint backlog; Task #3's recorded result was
  0 errors, 30 warnings and 342 infos. No analyzer rules were disabled.
* Every production authenticated-password caller was checked: Account Information
  calls the one API helper, which sends all three fields. The only intentionally
  missing confirmation request is the backend negative test. No obsolete standalone
  page import/route remains, and generic profile updates still forbid password fields.

The follow-up is limited to confirmation, account-screen placement, surrounding
auth UI consistency and regression coverage. No auth redesign, router extraction,
commit or push was performed.
