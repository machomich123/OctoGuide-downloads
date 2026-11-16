# Smart App Control: research into other projects

Investigated 2026-11-16. Current owner constraints: no mandatory signing, no submission/contact with Microsoft, no disabling Windows protection. No file or report has been sent to Microsoft. This document supersedes the submission proposal in UNSIGNED-WINDOWS-RELEASE.md.

## Conclusion

There is no verified fix here that makes the currently blocked 1.0.12 executable run immediately while meeting all three constraints. Other projects show real packaging fixes, signed distribution routes, or reports of reputation changing over time. None proves that renaming our updater or republishing the same unsigned application will make it accepted.

The public update remains paused. Installed 1.0.11 is preserved. The addon repair/import changes remain in source and the original tested executable remains available unchanged in repository history. Do not call this release installed or unblocked.

## Cases examined

| Project / primary source | What was actually reported or done | Relevance here |
| --- | --- | --- |
| [Windows-MCP #367](https://github.com/CursorTouch/Windows-MCP/issues/367) | A maintainer reports removing the generated unsigned console-entry-point EXE and using the project's normal Python module entry point with the existing signed Python interpreter. Closed as a duplicate of the fixed issue. | A genuine packaging fix for a redundant entry-point stub. Our pending-update.exe is the entire new managed launcher, with the same SHA-256 as the release EXE. Removing a redundant wrapper does not remove the blocked application in our case. Do not treat an interpreter as a generic way to run our blocked assembly. |
| [TeXstudio #3689](https://github.com/texstudio-org/texstudio/issues/3689) | Maintainer eventually supplied a signed binary; issue closed. | Verified upstream action, but does not meet the owner's no-signing choice. |
| [Daintree #5831](https://github.com/daintreehq/daintree/issues/5831) | Maintainer chose Microsoft Store distribution instead of the proposed SignPath route, with Store packaging changes linked to commits. | A different distribution model involving Microsoft certification/signing. Not a solution under the present constraints. The original signing proposal alone was not the implemented fix. |
| [RTK #3226](https://github.com/rtk-ai/rtk/issues/3226) | Reporter compares an unsigned old version that works with a new unsigned version that is blocked, and reports delays around releases. The issue remained open when examined. | Strong similarity to 1.0.11 versus 1.0.12. The report is not a measured guarantee that waiting one week will fix ours; no such deadline is established. Ignore the report's general claims about EV certificates as an unsigned solution. |
| [KeePass support discussion](https://sourceforge.net/p/keepass/discussion/329221/thread/b672765d07/) and [official FAQ](https://keepass.info/help/kb/faq.html#smartscreen) | User reports both installer and portable ZIP blocked; restoring the older version worked. Maintainer recommends waiting a few days. The official FAQ says KeePass executables are signed and discusses SmartScreen reputation. | Shows portable packaging does not necessarily resolve a Code Integrity block. It is not proof that an unsigned launcher will automatically be approved after a fixed wait. |
| [BrowserSkill #262](https://github.com/Tencent/BrowserSkill/issues/262) | Reports the same policy ID and an unsigned executable. Issue was closed without a documented remediation in the visible conversation. | Closed status alone is not evidence of a successful fix. |

## How this maps to our launcher

The blocked file's SHA-256 is `0DFCE6C793D1E7233944A6E6455CA90D01DFEF7077A67141184CAF0572107FCE`, identical to the tested 1.0.12 release. It is not a separately compiled updater stub. The existing launcher calls Process.Start on the new executable with `--replace`; Windows refuses that file before its update routine runs.

There are no embedded login loaders in this release. Removing those was sensible, but it did not give the new launcher publisher trust or establish reputation. A successful launch on a disposable CI runner did not reproduce this PC's enforcement decision.

Moving the exact blocked application to another path, changing an installer, running as administrator, or using a portable ZIP is not a verified solution to this recorded block. Download-warning guidance such as 'Run anyway' must not be confused with an enforced Smart App Control refusal.

## What can be done under the current constraints

- Preserve the working 1.0.11 while the 1.0.12 executable remains blocked. Do not repeatedly execute or regenerate the blocked file.
- Keep the exact existing 1.0.12 artifact stable. Its reputation might change without a manual submission, but neither these reports nor Microsoft's documentation gives a deadline or guarantee. Do not promise that time alone resolves it.
- Continue ordinary configuration/addon-content updates using the capabilities already present in the working launcher. These updates need not replace the native launcher EXE. New functionality such as the new repair button still needs an executable that Windows allows; it cannot be delivered into 1.0.11 merely by changing the manifest.
- For future development, minimize unnecessary native executable rebuilds and separate content/configuration from program releases. This reduces encounters with new executable identities; it does not make arbitrary future native updates guaranteed to run.
- If an immediate new native launcher remains mandatory, at least one of the constraints must change, or an actual independently verified compatibility fix must be found. No such fix has been established for this file. Do not bypass application control by hosting the blocked assembly inside another process.

## Releasing later

The source supports unsigned releases again. Release tooling requires a recorded successful run of the exact hash on the affected Windows installation, with protection unchanged, in addition to CI/provenance checks. Do not fabricate that evidence or unpause the known-blocked release to make the task appear finished.

Official interpretation of app-intelligence versus signatures:
https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview

Official explanation of file-hash reputation and the difference from publisher reputation:
https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation

These official pages explain the mechanism. They do not provide a developer setting guaranteeing approval for each unsigned build.
