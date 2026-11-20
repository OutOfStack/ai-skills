---
name: winget-updates
description: Review or install Windows software updates through WinGet, limited to major and minor version increases. Patch-only bumps, pinned packages, and unknown versions are skipped. Use whenever a Windows user asks which apps need updating, wants to update their software or packages, or mentions winget upgrade, even if they say "update everything".
metadata:
  version: "0.1.0"
---

# Update WinGet packages

1. Run `winget upgrade --accept-source-agreements --disable-interactivity`.
   If the session cannot launch WinGet, give the user the command to run in
   local PowerShell and use the output they provide.
2. Compare installed and available versions numerically. Select a package
   if the first component increases, or if the first stays the same and
   the second increases. Apply the same rule to two-component versions
   and year-based versions such as Lens. Skip changes confined to later
   components, unknown or ambiguous versions, and pinned packages.
3. If the user asked for a review, report the eligible updates. If they
   asked to update, run one command per eligible package with the exact ID,
   source, and version from the listing. Skip dependency upgrades.

   ```powershell
   winget upgrade --id $id --exact --source $source --version $version `
     --skip-dependencies --accept-source-agreements `
     --accept-package-agreements --disable-interactivity
   ```

4. Skip `MSYS2.MSYS2` even if WinGet lists it under packages requiring
   explicit targeting. For other packages in that section, check whether
   their manifest permits the upgrade before targeting them. Record
   confirmed denials by exact package ID. Treat installer failures,
   elevation requirements, and missing matches as problems to diagnose.
5. Continue with the remaining packages after a failure. Rerun the upgrade
   listing, check installed versions where needed, and report what updated
   and what still needs action. If WinGet cannot run in the session, give
   the user the exact commands and use their results to verify the run.
