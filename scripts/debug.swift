// Drives a debug build of Portrero (see Sources/Portrero/App/DebugHooks.swift).
//   swift scripts/debug.swift pane <general|browsers|linkRules|fileTypes|fileRules>
//   swift scripts/debug.swift link <url>
//   swift scripts/debug.swift state <directory>
//   swift scripts/debug.swift key <down|up|return|esc|tab|1-5|cmd-c|cmd-comma>
//   swift scripts/debug.swift shot <file.png>
import Foundation

let args = CommandLine.arguments.dropFirst()
guard let command = args.first, let value = args.dropFirst().first else {
    print("usage: debug.swift pane <name> | link <url> | state <dir> | key <name> | shot <file.png>")
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    .init("app.portrero.debug.\(command)"), object: value, userInfo: nil, deliverImmediately: true
)
