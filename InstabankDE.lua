-- ============================================================
-- MoneyMoney Web Banking Extension
-- Instabank ASA (DE) – netbank.instabank.de
-- Version: 1.40
--
-- Changes in 1.40:
--  - Bearer Token wird nach Login in LocalStorage gespeichert
--  - Beim nächsten Sync wird der Token wiederverwendet (kein OTP nötig)
--  - Fallback auf normalen OTP-Flow wenn Token abgelaufen
-- Changes in 1.39:
--  - Step 1 now triggers the SMS directly (no separate confirmation step)
--    → only one dialog window, no gap between steps during a Rundruf
--  - All dialog and status texts translated to German
--  - Stale LocalStorage state is cleared at the start of each new login
-- Changes in 1.38:
--  - SMS-TAN-Bestätigungsdialog auf Deutsch mit Hinweis auf „Fertig"-Schaltfläche
--
-- Changes in 1.37:
--  - Added confirmation step before SMS OTP to prevent duplicate SMS
--    when refreshing all accounts simultaneously
-- Changes in 1.36:
--  - Clear error message when password is missing after app restart
-- Changes in 1.35:
--  - Removed sensitive debug output (session token, TAN response, bearer, account, transactions)
-- Changes in 1.34:
--  - Reverted LocalStorage to bracket notation (set/get/remove unavailable in this MoneyMoney version)
--  - Replaced custom JSON parser with built-in JSON object
--  - Set Accept header to application/json
--
-- Login flow (2 steps via IOtpAuthentication):
--   1. Enter credentials → POST /api/IOtpAuthentication step=0 → session token → show TAN dialog
--   2. POST /api/IOtpAuthentication step=1, otp=SMS TAN → confirmed
--      POST /api/IOtpAuthentication step=4, password=... → FvAuthorization Bearer
--
-- Username = mobile number (e.g. +4917612345678)
-- Password = account password
-- TAN      = SMS TAN (requested via 2FA dialog)
--
-- API endpoints:
--   Accounts:     GET /api/IAccount
--   Transactions: GET /api/ITransaction?accounts[]=IBAN&dateFrom=...&dateTo=...
-- ============================================================

WebBanking {
  version     = 1.40,
  url         = "https://netbank.instabank.de",
  services    = {"Instabank Kreditkarte (DE)"},
  description = "Instabank ASA – Credit Card Germany"
}

local baseURL          = "https://netbank.instabank.de"
local connection       = nil
local bearerToken      = nil
local sessionToken     = nil
local mobile           = nil
local _pendingPassword = nil  -- password kept in RAM only, never persisted

-- ============================================================
-- SupportsBank
-- ============================================================
function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Instabank Kreditkarte (DE)"
end

-- ============================================================
-- InitializeSession2 – 2FA Login
--   step=1: Accept credentials → trigger SMS → return TAN dialog
--   step=2: Accept SMS TAN → verify → fetch Bearer token → done
-- ============================================================
function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  if not connection then
    connection = Connection()
    connection.language  = "de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7"
    connection.useragent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " ..
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  end

  if step == 1 then
    -- Gespeicherten Bearer Token prüfen und ggf. wiederverwenden
    local storedToken = LocalStorage["_bearer_token"]
    if storedToken and #storedToken > 0 then
      bearerToken = storedToken
      MM.printStatus("Gespeichertes Token wird geprüft ...")
      local ok, result = pcall(apiGet, "/api/IAccount?canTransfer=&customer=&customFilter=&internalTransferSource=&internalTransferTarget=", "CustomAccount", "details")
      if ok and result then
        -- Token ist noch gültig: aktualisierten Token speichern und Login überspringen
        LocalStorage["_bearer_token"] = bearerToken
        MM.printStatus("Token gültig, kein OTP nötig.")
        return nil
      else
        -- Token abgelaufen: löschen und normalen Login starten
        bearerToken = nil
        LocalStorage["_bearer_token"] = nil
        MM.printStatus("Token abgelaufen, SMS TAN wird angefordert ...")
      end
    end

    -- credentials[1] = mobile number, credentials[2] = password
    local rawMobile = credentials[1] or ""
    mobile = rawMobile:gsub("%s", ""):gsub("%-", "")

    -- Normalize: strip "00" prefix first, then "+"
    if mobile:sub(1, 2) == "00" then
      mobile = mobile:sub(3)
    elseif mobile:sub(1, 1) == "+" then
      mobile = mobile:sub(2)
    end

    -- Keep password in RAM only, never write to LocalStorage
    _pendingPassword = credentials[2] or ""

    -- Clear any stale state from a previous session
    LocalStorage["_pending_session"] = nil
    LocalStorage["_pending_mobile"]  = nil

    -- Trigger SMS immediately so there is only one dialog window
    MM.printStatus("SMS TAN wird angefordert ...")
    local body = JSON():set({
      ["$id"] = "0",
      step    = 0,
      mobile  = mobile,
    }):json()

    local resp = apiPost("/api/IOtpAuthentication", body, "OtpAuthentication", true)
    if not resp then
      return "Fehler: Server nicht erreichbar."
    end

    local parsed = JSON(resp):dictionary()
    sessionToken = (parsed and parsed.session) or ""

    -- Persist session token and mobile for step 2
    LocalStorage["_pending_session"] = sessionToken
    LocalStorage["_pending_mobile"]  = mobile

    return {
      title     = "Instabank SMS TAN",
      challenge = "Eine SMS TAN wurde an Ihre Mobilnummer gesendet.\n\nBitte geben Sie die TAN ein:",
      label     = "SMS TAN",
    }

  elseif step == 2 then
    -- Restore session and mobile from LocalStorage if needed
    sessionToken = (sessionToken and sessionToken ~= "") and sessionToken
                   or LocalStorage["_pending_session"] or ""
    mobile       = (mobile and mobile ~= "") and mobile
                   or LocalStorage["_pending_mobile"] or ""

    -- Fetch password from RAM and clear it immediately.
    -- If missing (e.g. after app restart between step 1 and 2),
    -- clean up temporary data and return a clear error message.
    if not _pendingPassword or _pendingPassword == "" then
      LocalStorage["_pending_session"] = nil
      LocalStorage["_pending_mobile"]  = nil
      return "Sitzung abgelaufen. Bitte melden Sie sich erneut an (Mobilnummer und Passwort eingeben)."
    end
    local password = _pendingPassword
    _pendingPassword = nil

    local tan = (credentials[1] or ""):match("^%s*(.-)%s*$") or ""

    -- Verify TAN
    MM.printStatus("TAN wird geprüft ...")
    local body2 = JSON():set({
      ["$id"] = "0",
      session = sessionToken,
      step    = 1,
      mobile  = mobile,
      otp     = tan,
    }):json()

    local resp2 = apiPost("/api/IOtpAuthentication", body2, "OtpAuthentication", true)
    if not resp2 then
      return LoginFailed
    end

    -- Send password → fetch Bearer token
    MM.printStatus("Anmeldung läuft ...")
    local body3 = JSON():set({
      ["$id"]    = "0",
      session    = sessionToken,
      step       = 4,
      mobile     = mobile,
      password   = password,
    }):json()

    local resp3, _, _, _, headers3 = connection:request(
      "POST", baseURL .. "/api/IOtpAuthentication", body3,
      "application/json; charset=UTF-8",
      buildHeaders("OtpAuthentication", "default", true)
    )

    -- Extract Bearer token from response header
    local newToken = extractBearer(headers3)
    if newToken then
      bearerToken = newToken
    end

    -- Fallback: token from response body
    if (not bearerToken or #bearerToken == 0) and resp3 then
      local parsed3 = JSON(resp3):dictionary()
      if parsed3 then
        bearerToken = parsed3.token or parsed3.accessToken
      end
    end

    if not bearerToken or #bearerToken == 0 then
      return LoginFailed
    end

    -- Clean up temporary LocalStorage entries
    LocalStorage["_pending_session"] = nil
    LocalStorage["_pending_mobile"]  = nil

    -- Bearer Token für nächsten Sync persistieren
    LocalStorage["_bearer_token"] = bearerToken

    -- Call IState: puts the server-side session into the "logged-in" state.
    -- The response content is irrelevant to us.
    MM.printStatus("Sitzung wird initialisiert ...")
    apiGet("/api/IState", "StateManager", "null")

    MM.printStatus("Erfolgreich angemeldet.")
    return nil
  end
end

-- ============================================================
-- ListAccounts
-- ============================================================
function ListAccounts(knownAccounts)
  MM.printStatus("Loading accounts ...")

  local raw = apiGet(
    "/api/IAccount?canTransfer=&customer=&customFilter=" ..
    "&internalTransferSource=&internalTransferTarget=",
    "CustomAccount", "details"
  )
  if not raw then
    return "Error: Account list not reachable."
  end
  local data = JSON(raw):dictionary()
  if not data then
    return "Error: No accounts found."
  end

  local accounts = {}
  local seen     = {}

  for _, acct in ipairs(data) do
    local iban = acct.accountName
    if iban and not seen[iban] and acct.accountType then
      seen[iban] = true

      local name     = acct.displayName or acct.product or "Instabank Credit Card"
      local currency = (type(acct.currency) == "string" and #acct.currency == 3
                        and acct.currency) or "EUR"

      -- balance and limit are in the nested balances object
      local balObj  = type(acct.balances) == "table" and acct.balances or acct
      local balance = tonumber(balObj.balance) or 0

      -- Account holder from debtors array
      local debtors   = type(acct.debtors) == "table" and acct.debtors or {}
      local debtor    = debtors[1] or {}
      local firstName = debtor.firstName or ""
      local lastName  = debtor.lastName  or ""
      local owner     = (firstName .. " " .. lastName):match("^%s*(.-)%s*$")

      -- Cache balance in LocalStorage as fallback for RefreshAccount
      -- in case the IAccount request fails there
      LocalStorage[iban .. "_currency"] = currency
      LocalStorage[iban .. "_balance"]  = tostring(balance)

      table.insert(accounts, {
        name          = name,
        owner         = owner,
        accountNumber = iban,
        bankCode      = "20220800",
        currency      = currency,
        bic           = "IKBDDEDD",
        iban          = iban,
        type          = AccountTypeCreditCard,
      })
    end
  end

  if #accounts == 0 then
    return "Error: No accounts found. Response: " .. raw:sub(1, 300)
  end
  return accounts
end

-- ============================================================
-- RefreshAccount
-- ============================================================
function RefreshAccount(account, since)
  local iban = account.accountNumber
  MM.printStatus("Loading transactions for " .. iban .. " ...")

  -- Fetch current balance for this account from the server.
  -- MoneyMoney only calls ListAccounts on the first sync –
  -- after that it goes directly to RefreshAccount, hence a separate request.
  local balance        = 0
  local pendingBalance = nil

  local acctRaw = apiGet(
    "/api/IAccount?canTransfer=&customer=&customFilter=" ..
    "&internalTransferSource=&internalTransferTarget=",
    "CustomAccount", "details"
  )
  if acctRaw then
    local data = JSON(acctRaw):dictionary()
    if data then
      for _, acct in ipairs(data) do
        if acct.accountName == iban and acct.accountType then
          local balObj = type(acct.balances) == "table" and acct.balances or acct
          local b = tonumber(balObj.balance)
          local p = tonumber(balObj.amountBlocked)
          if b then
            -- Credit cards: positive balance = debt → show as negative in MoneyMoney.
            -- Explicit zero check prevents "-0" in the display.
            balance = (b ~= 0) and -b or 0
          end
          if p and p ~= 0 then
            pendingBalance = -p
          end
          break
        end
      end
    end
  else
    -- Fallback: last cached value from ListAccounts
    local cached = tonumber(LocalStorage[iban .. "_balance"] or "0") or 0
    balance = (cached ~= 0) and -cached or 0
  end

  -- Query time range
  local toTS   = os.time()
  local fromTS = since or (toTS - 365 * 24 * 3600)
  local dateFrom = os.date("!%Y-%m-%dT%H:%M:%S.000Z", fromTS)
  local dateTo   = os.date("!%Y-%m-%dT%H:%M:%S.000Z", toTS)
  print("Range: " .. dateFrom .. " to " .. dateTo)

  local txURL = "/api/ITransaction" ..
    "?accounts%5B%5D=" .. MM.urlencode(iban) ..
    "&amountFrom=&amountTo=&creditOnly=false" ..
    "&dateFrom="  .. MM.urlencode(dateFrom) ..
    "&dateTo="    .. MM.urlencode(dateTo) ..
    "&debitOnly=false&description=&maxRows=&onlyCount=&targetAccount=&filterChanged=false"

  local txRaw = apiGet(txURL, "Transaction", "details")
  local transactions = {}

  if txRaw and #txRaw > 0 then
    local txData = JSON(txRaw):dictionary()
    if txData then
      for _, tx in ipairs(txData) do
        -- Only process real transactions with bookDate
        if tx.bookDate then
          local t = parseTx(tx, since)
          if t then table.insert(transactions, t) end
        end
      end
    end
  end

  table.sort(transactions, function(a, b) return a.bookingDate > b.bookingDate end)
  print("Balance: " .. balance .. " | Transactions: " .. #transactions)

  return {
    balance        = balance,
    pendingBalance = pendingBalance,
    transactions   = transactions,
  }
end

-- ============================================================
-- EndSession
-- ============================================================
function EndSession()
  -- No logout API call: Instabank has no valid logout endpoint.
  -- The session expires server-side after timeout.
  -- Note: _bearer_token bleibt in LocalStorage für den nächsten Sync.
  bearerToken      = nil
  sessionToken     = nil
  mobile           = nil
  _pendingPassword = nil

  -- Clean up temporary login data for safety
  LocalStorage["_pending_session"] = nil
  LocalStorage["_pending_mobile"]  = nil

  return nil
end

-- ============================================================
-- Helper functions
-- ============================================================

-- Extract Bearer token case-insensitively from response header table.
function extractBearer(headers)
  if not headers then return nil end
  for k, v in pairs(headers) do
    if type(k) == "string" and k:lower() == "fvauthorization" then
      if v and #v > 0 then
        return v:gsub("^[Bb]earer%s+", "")
      end
    end
  end
  return nil
end

-- Build standard request headers.
-- isAuth=true → do not send Bearer token (login phase)
function buildHeaders(fvcomponent, fvinstance, isAuth)
  local h = {
    ["Accept"]           = "application/json",
    ["Content-Type"]     = "application/json; charset=UTF-8",
    ["X-Requested-With"] = "XMLHttpRequest",
    ["Referer"]          = baseURL .. "/",
    ["Origin"]           = baseURL,
    ["DNT"]              = "1",
  }
  if bearerToken and not isAuth then
    h["FvAuthorization"] = "Bearer " .. bearerToken
  end
  if fvcomponent then
    h["fvcomponent"]         = fvcomponent
    h["fvcomponentinstance"] = fvinstance or "default"
  end
  return h
end

-- GET request; updates bearerToken if the response provides a new one.
function apiGet(path, fvcomponent, fvinstance)
  local content, _, _, _, headers = connection:request(
    "GET", baseURL .. path, nil, nil,
    buildHeaders(fvcomponent, fvinstance, false)
  )
  local newToken = extractBearer(headers)
  if newToken then bearerToken = newToken end
  return (content and #content > 0) and content or nil
end

-- POST request; updates bearerToken if the response provides a new one.
-- isAuth=true → do not send Bearer token in request header (login phase)
function apiPost(path, body, fvcomponent, isAuth)
  local content, _, _, _, headers = connection:request(
    "POST", baseURL .. path, body, "application/json; charset=UTF-8",
    buildHeaders(fvcomponent, "default", isAuth)
  )
  local newToken = extractBearer(headers)
  if newToken then bearerToken = newToken end
  return (content and #content > 0) and content or nil
end

-- Build transaction from raw fields.
-- Returns nil for invalid or outdated transactions.
function parseTx(tx, since)
  local bookingDate = parseDate(tx.bookDate or tx.valueDate or "")
  if not bookingDate then return nil end
  if since and bookingDate < since then return nil end

  local amount = 0
  if (tx.creditAmount or 0) > 0 then
    amount = tx.creditAmount
  elseif (tx.debitAmount or 0) > 0 then
    amount = -tx.debitAmount
  else
    return nil  -- skip zero-amount entries
  end

  local purpose = tx.message or tx.description or ""
  local desc    = tx.description or ""
  if #desc > 0 and desc ~= purpose then
    purpose = purpose .. " – " .. desc
  end

  -- valueDate: for credit cards the value date is often more relevant
  -- than the booking date (e.g. invoice payments with a future date)
  local valueDate = parseDate(tx.valueDate or "")

  return {
    bookingDate = bookingDate,
    valueDate   = valueDate,
    purpose     = purpose,
    amount      = amount,
    currency    = "EUR",
    booked      = tx.isBooked ~= false,
  }
end

-- Convert ISO-8601 date (YYYY-MM-DD...) to Unix timestamp.
-- Time set to 12:00 to avoid DST edge cases.
function parseDate(str)
  if not str or #str == 0 then return nil end
  local y, m, d = str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if y then
    return os.time({
      year  = tonumber(y),
      month = tonumber(m),
      day   = tonumber(d),
      hour  = 12, min = 0, sec = 0
    })
  end
  print("Date not parseable: " .. str)
  return nil
end
