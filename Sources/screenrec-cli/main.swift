import Foundation
import RecorderCore

// Unbuffered stdout so diagnostics survive crashes and pipes (docs/02 §10).
setvbuf(stdout, nil, _IONBF, 0)

print("screenrec-cli — M0 skeleton (RecorderCore \(CoreInfo.version))")
print("Subcommands arrive with M0-T5 (record dry-run, --list-mics).")
