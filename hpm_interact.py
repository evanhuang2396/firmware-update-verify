#!/usr/bin/env python3
# Replaces `expect` for interactive HPM upgrade prompts.
# Usage: uv run --with pexpect hpm_interact.py <FULL_CMD> <LOG_FILE>
import sys
import pexpect


def main():
    if len(sys.argv) != 3:
        print("[ERROR] Usage: hpm_interact.py <FULL_CMD> <LOG_FILE>", file=sys.stderr)
        sys.exit(1)

    cmd, log_file_path = sys.argv[1], sys.argv[2]

    with open(log_file_path, "a") as logf:
        child = pexpect.spawn(
            "bash", ["-lc", cmd],
            timeout=1200,
            logfile=logf,
            encoding="utf-8",
        )

        while True:
            idx = child.expect([
                r"Continue ignoring",
                r"Services may be affected",
                pexpect.TIMEOUT,
                pexpect.EOF,
            ])
            if idx in (0, 1):
                child.sendline("y")
            elif idx == 2:
                print("\n[ERROR] Timed out waiting for prompt or completion", file=sys.stderr)
                sys.exit(1)
            else:  # EOF
                child.close()
                rc = child.exitstatus if child.exitstatus is not None else child.signalstatus
                if rc:
                    print(f"\n[ERROR] Command exited with rc={rc}", file=sys.stderr)
                    sys.exit(rc)
                print("\n=== spv_ipmi process ended ===")
                break


if __name__ == "__main__":
    main()
