# Blizzard API key for the auction house collector

The offline collector (#215) reads Blizzard's Forever auction house export (believed to refresh
about hourly; the collector logs each export's time, so we can measure it). It needs a free
API client from Battle.net, stored as two repository secrets. A repo admin has to do this.

The collector reads the **EU** export. If your characters are on US, say so before adding the
secrets.

1. Sign in at https://develop.battle.net/access/clients and choose **Create client**.
   - Client name: `better-ah collector`
   - Redirect URLs: leave empty (the collector uses client credentials, with no sign-in redirect).
   - Service URL: `https://github.com/chsko/better-ah`
   - Intended use: "Auction house price stats for my own WoW Forever addon."
2. Save, then copy the **Client ID** and **Client Secret**.
3. Open https://github.com/chsko/better-ah/settings/secrets/actions and add two
   **repository secrets**:
   - `BLIZZARD_CLIENT_ID`: the client ID
   - `BLIZZARD_CLIENT_SECRET`: the client secret
4. Open https://github.com/chsko/better-ah/settings/pages and set **Source** to **GitHub Actions**.
5. Open **Actions > AH collect > Run workflow** to try it now. The log shows each export's
   `Last-Modified` and what was recorded, and https://chsko.github.io/better-ah/ shows
   "Collecting since" after the first run.

Don't paste the secret anywhere else (issues, chat, commits). If it leaks, open the client
on develop.battle.net, generate a new secret, and update the repository secret.

GitHub turns off scheduled workflows in a public repo after 60 days without commits. If the probe
or collector stops, re-enable it under **Actions**.
