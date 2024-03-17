# Security-related tasks

{! administration/CLI_tasks/general_cli_task_info.include !}

!!! danger
    Many of these tasks were written in response to a patched exploit.
    It is recommended to run those very soon after installing its respective security update.
    Over time with db migrations they might become less accurate or be removed altogether.
    If you never ran an affected version, there’s no point in running them.

## Spoofed AcitivityPub objects exploit (2024-03, fixed in 3.11.1)

### Search for uploaded spoofing payloads

Scans local uploads for spoofing payloads.
If the instance is not using the local uploader it was not affected.
Attachments wil be scanned anyway in case local uploader was used in the past.

!!! note
    This cannot reliably detect payloads attached to deleted posts.

=== "OTP"

    ```sh
    ./bin/pleroma_ctl security spoof-uploaded
    ```

=== "From Source"

    ```sh
    mix pleroma.security spoof-uploaded
    ```
