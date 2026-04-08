# MoneyMoney Extension – Instabank ASA

A [MoneyMoney](https://moneymoney-app.com) extension for **Instabank ASA (DE)** via the [Instabank Netbank](https://netbank.instabank.de) web portal. Fetches credit card balances and transactions.

---

## Features

- Supports **Credit Card** accounts in EUR
- Fetches up to **365 days** of transaction history
- **SMS 2FA** — confirmation dialog before OTP is triggered (prevents duplicate SMS when refreshing all accounts at once)
- Fetches pending (blocked) balance separately

## Requirements

- [MoneyMoney](https://moneymoney-app.com) for macOS (any recent version)
- An **Instabank Netbank** account at [netbank.instabank.de](https://netbank.instabank.de)
- Your **mobile number** and **Instabank password**

> **Note:** This extension is for Instabank Germany (netbank.instabank.de) credit card accounts. Instabank ASA is a Norwegian bank offering credit cards in Germany.

## Installation

### Option A — Direct download

1. Download [`InstabankDE.lua`](InstabankDE.lua)
2. Move it into MoneyMoney's Extensions folder:
   ```
   ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/
   ```
3. In MoneyMoney, go to **Help → Show Database in Finder** if you need to locate the folder.
4. Reload extensions in MoneyMoney: right-click any account → **Reload Extensions** (or restart the app).

### Option B — Clone the repository

```bash
git clone https://github.com/davyd15/moneymoney-instabank.git
cp moneymoney-instabank/InstabankDE.lua \
  ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/
```

## Setup in MoneyMoney

1. Open MoneyMoney and add a new account: **File → Add Account…**
2. Search for **"Instabank"**
3. Select **Instabank Kreditkarte (DE)**
4. Enter your **mobile number** (e.g. `+4917612345678`) and **password**
5. Click **Next** — MoneyMoney will ask you to confirm the SMS TAN request, then send the OTP

## Supported Account Types

| Type | Description |
|------|-------------|
| Credit Card | Instabank Visa credit card (Germany) |

## Limitations

- **EUR only** — foreign currency transactions are shown in EUR
- **Max 365 days** history per refresh (portal limitation)
- Requires SMS 2FA on every new session — no persistent token storage

## Troubleshooting

**"Login failed" / credentials rejected**
- Make sure you are using your **Instabank Netbank credentials**, not the Instabank mobile app credentials
- Try logging in at [netbank.instabank.de](https://netbank.instabank.de) in your browser to verify your credentials

**Extension not appearing in MoneyMoney**
- Confirm the `.lua` file is in the correct Extensions folder (see Installation above)
- Reload extensions or restart MoneyMoney

**"Session expired" error between login steps**
- This can happen if MoneyMoney restarts between the credential entry and TAN entry steps
- Simply start the login process again from the beginning

**Transactions missing / history too short**
- The portal limits history to 365 days. Older transactions cannot be retrieved.

## Changelog

| Version | Changes |
|---------|---------|
| 1.37 | Added confirmation step before SMS OTP to prevent duplicate SMS when refreshing all accounts simultaneously |
| 1.36 | Clear error message when password is missing after app restart |
| 1.35 | Removed sensitive debug output from log |
| 1.34 | Corrected LocalStorage bracket notation; replaced custom JSON parser with built-in; fixed Accept header |

## Contributing

Bug reports and pull requests are welcome. If Instabank changes its login flow or API, please open an issue with the MoneyMoney log output — that makes it much easier to diagnose.

To test changes locally, copy the `.lua` file into the Extensions folder and reload extensions in MoneyMoney.

## Disclaimer

This extension is an independent community project and is **not affiliated with, endorsed by, or supported by Instabank ASA** or the MoneyMoney developers. Use at your own risk. Credentials are handled solely by MoneyMoney's built-in secure storage and are never transmitted to any third party.

## License

MIT — see [LICENSE](LICENSE)
