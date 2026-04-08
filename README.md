# MoneyMoney Extension – Instabank ASA

A [MoneyMoney](https://moneymoney-app.com) extension for **Instabank ASA Germany** that connects to the [Instabank Netbank](https://netbank.instabank.de) portal to import credit card balances and transactions.

---

## Features

- Imports **credit card** balances and up to **365 days** of transaction history
- **SMS 2FA** with a confirmation step before the OTP is triggered — prevents duplicate SMS messages when MoneyMoney refreshes multiple accounts simultaneously
- Tracks **pending (blocked) charges** separately from the posted balance
- Bearer token is automatically refreshed from every response header — no repeated logins during a session

## How It Works

The extension implements MoneyMoney's `WebBanking` Lua API and communicates with Instabank's JSON REST API at `netbank.instabank.de`.

### Authentication

Login uses a deferred 3-step SMS 2FA flow via `POST /api/IOtpAuthentication`:

| Step | Action |
|------|--------|
| 1 | Credentials are entered; no network call is made yet |
| 2 | User confirms the OTP dialog — only then is the SMS triggered (step 0: returns session token) |
| 3 | TAN is verified (step 1), then the session is exchanged for an `FvAuthorization` Bearer token (step 4) |

**Security:** The password is held in RAM only (`_pendingPassword`) and cleared immediately after use. It is never written to `LocalStorage` or any other persistent storage.

The `FvAuthorization` Bearer token is extracted from every API response header and refreshed automatically, keeping the session alive across multiple account refreshes without re-authentication.

### Data Retrieval

- `GET /api/IAccount` — fetches all accounts with balances; called on every refresh since MoneyMoney only invokes `ListAccounts` on the first sync
- `GET /api/ITransaction` — fetches transactions filtered by IBAN and date range (up to 365 days)

Credit card balances are sign-inverted on import: a positive value from the API represents outstanding debt and is returned as a negative amount to MoneyMoney.

## Requirements

- [MoneyMoney](https://moneymoney-app.com) for macOS (any recent version)
- An active Instabank Germany credit card account with access to [netbank.instabank.de](https://netbank.instabank.de)
- Your registered **mobile number** and **Instabank password**

## Installation

### Option A — Direct download

1. Download [`InstabankDE.lua`](InstabankDE.lua)
2. Move it into MoneyMoney's Extensions folder:
   ```
   ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/
   ```
3. Reload extensions: right-click any account in MoneyMoney → **Reload Extensions** (or restart the app)

### Option B — Clone the repository

```bash
git clone https://github.com/davyd15/moneymoney-instabank.git
cp moneymoney-instabank/InstabankDE.lua \
  ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/
```

## Setup in MoneyMoney

1. Open MoneyMoney → **File → Add Account…**
2. Search for **"Instabank"** and select **Instabank Kreditkarte (DE)**
3. Enter your **mobile number** (e.g. `+4917612345678`) and **password**
4. A confirmation dialog appears — confirm to trigger the SMS OTP
5. Enter the TAN from the SMS to complete login

## Limitations

- **EUR only** — the Instabank Germany credit card is EUR-denominated
- **Max 365 days** of history per refresh (portal API limitation)
- A new SMS OTP is required for each new session — there is no persistent token

## Troubleshooting

**"Login failed" / credentials rejected**
- Verify your credentials at [netbank.instabank.de](https://netbank.instabank.de) in a browser
- Make sure you are not using credentials from the Instabank mobile app — Netbank uses a separate login

**Extension not appearing in MoneyMoney**
- Confirm the `.lua` file is in the correct Extensions folder (see Installation above)
- Reload extensions or restart MoneyMoney

**"Session expired" error during login**
- This can happen if MoneyMoney is restarted between the credential step and the TAN step
- Start the login flow again from the beginning

**Transactions missing or history too short**
- The portal API limits history to 365 days — older transactions cannot be retrieved

## Changelog

| Version | Changes |
|---------|---------|
| 1.37 | Added confirmation step before SMS OTP — prevents duplicate SMS when refreshing all accounts simultaneously |
| 1.36 | Clear error message when password is missing after app restart |
| 1.35 | Removed sensitive debug output from the MoneyMoney log |
| 1.34 | Fixed LocalStorage bracket notation; replaced custom JSON parser with built-in; fixed Accept header |

## Contributing

Bug reports and pull requests are welcome. If Instabank changes its login flow or API endpoints, please open an issue and include the MoneyMoney log output — it makes diagnosing the problem much faster.

To test changes locally, copy the updated `.lua` file into the Extensions folder and reload extensions in MoneyMoney.

## Disclaimer

This is an independent community project and is **not affiliated with, endorsed by, or supported by Instabank ASA** or the MoneyMoney developers. Use at your own risk. Credentials are handled solely by MoneyMoney's built-in secure storage and are never transmitted to any third party.

## License

MIT — see [LICENSE](LICENSE)
