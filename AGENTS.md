# Agent guide for Swift and SwiftUI

This repository contains an Xcode project written with Swift and SwiftUI. Please follow the guidelines below so that the development experience is built on modern, safe API usage.

You are operating in an environment where ast-grep is installed. For any code search that requires understanding of syntax or code structure, you should default to using ast-grep --lang [language] -p '<pattern>'. Adjust the --lang flag as needed for the specific programming language. Avoid using text-only search tools unless a plain-text search is explicitly requested.

### Code Generation Patterns

When generating Swift code, follow these specific patterns:

1. **View Structures**: Always create separate `View` structs rather than computed properties
2. **Error Handling**: Use `do-catch` blocks with proper error messages, never `try?`
3. **URL Handling**: Use `URL.homeDirectory` and `appending(path:)` instead of string concatenation
4. **String Operations**: Prefer Swift-native methods like `replacing(_:with:)` over Foundation methods
5. **SwiftUI Modifiers**: Use `foregroundStyle()` instead of `foregroundColor()`, `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`
6. **Color Usage**: Use SwiftUI-native colors or properly wrap NSColor with `Color(NSColor.xxx)` - never use invalid Color properties like `Color.windowBackground`

### Common Search Patterns

Use these ast-grep patterns to find deprecated code:

```bash
# Find old Foundation string methods
ast-grep --lang swift -p 'replacingOccurrences(of: $A, with: $B)'

# Find NSHomeDirectory usage
ast-grep --lang swift -p 'NSHomeDirectory()'

# Find try? patterns
ast-grep --lang swift -p 'try? $EXPR'

# Find foregroundColor usage
ast-grep --lang swift -p '.foregroundColor($COLOR)'

# Find cornerRadius usage
ast-grep --lang swift -p '.cornerRadius($RADIUS)'

# Find fontWeight usage
ast-grep --lang swift -p '.fontWeight(.bold)'

# Find NSMutableData in concurrent contexts (potential Sendable issues)
ast-grep --lang swift -p 'NSMutableData()'

# Find non-Sendable captures in closures
ast-grep --lang swift -p 'readabilityHandler = { $CAPTURE in $BODY }'

# Find main actor isolation violations
ast-grep --lang swift -p '@MainActor $DECL'

# Find potential concurrency issues with mutable state
ast-grep --lang swift -p 'var $VAR = false; $CLOSURE { $VAR = true }'
```

## Role

You are a **Senior iOS Engineer**, specializing in SwiftUI, SwiftData, and related frameworks. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines.

## Core instructions

- Target iOS 26.0 or later. (Yes, it definitely exists.)
- Swift 6.2 or later, using modern Swift concurrency.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.

## Swift instructions

- Always mark `@Observable` classes with `@MainActor`.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app's documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Use proper error handling instead of `try?` - handle errors explicitly or propagate them appropriately.
- Prefer `URL.homeDirectory` over `NSHomeDirectory()` for getting the user's home directory.
- When working with file paths, use modern URL APIs instead of string manipulation.

## SwiftUI instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap's location or the number of taps. All other usages should use `Button`.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer` to `UIGraphicsImageRenderer`.
- Don't apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code. Use SwiftUI-native colors or wrap NSColor with `Color(NSColor.xxx)` when necessary, but avoid direct NSColor usage in SwiftUI contexts.
- Always add accessibility modifiers such as `.accessibilityLabel()`, `.accessibilityHint()`, and `.accessibilityValue()` to interactive elements whenever possible to ensure the app is accessible to users with disabilities.

## Swift 6 Concurrency Guidelines

### Real-World Example: Process Output Collection
The concurrency issues we fixed in BrewService demonstrate common patterns you'll encounter:

```swift
// ❌ Problem: NSMutableData captured in @Sendable closure
let outputData = NSMutableData()
process.standardOutput.readabilityHandler = { handle in
    let data = handle.availableData
    outputData.append(data) // Error: NSMutableData is not Sendable
}

// ✅ Solution: Thread-safe wrapper with proper synchronization
let outputData = NSMutableData()
let dataLock = NSLock()

nonisolated class DataWrapper: @unchecked Sendable {
    private let data: NSMutableData
    private let lock: NSLock
    
    init(data: NSMutableData, lock: NSLock) {
        self.data = data
        self.lock = lock
    }
    
    nonisolated func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }
}

let wrapper = DataWrapper(data: outputData, lock: dataLock)
process.standardOutput.readabilityHandler = { handle in
    let data = handle.availableData
    wrapper.append(data) // ✅ Safe: wrapper is Sendable
}
```

### Sendable Conformance
- **Always prefer value types (structs, enums) for concurrent code** - they are implicitly Sendable
- **Mark classes as `@unchecked Sendable` only when necessary** - and document why thread safety is guaranteed
- **Use actors for shared mutable state** - instead of complex locking mechanisms
- **Avoid NSMutableData in concurrent contexts** - use Data with proper synchronization instead

### Common Concurrency Patterns

#### ✅ Safe: Using Data with NSLock
```swift
// Good - Thread-safe data collection
let dataLock = NSLock()
var collectedData = Data()

handler = { handle in
    let newData = handle.availableData
    if !newData.isEmpty {
        dataLock.lock()
        collectedData.append(newData)
        dataLock.unlock()
    }
}
```

#### ❌ Unsafe: Capturing NSMutableData in closures
```swift
// Bad - NSMutableData is not Sendable
let outputData = NSMutableData()
handler = { handle in
    let data = handle.availableData
    outputData.append(data) // Compiler error: NSMutableData is not Sendable
}
```

#### ✅ Safe: Sendable wrapper for non-Sendable types
```swift
// Good - Proper Sendable wrapper
nonisolated class DataWrapper: @unchecked Sendable {
    private let data: NSMutableData
    private let lock = NSLock()
    
    init(data: NSMutableData) {
        self.data = data
    }
    
    nonisolated func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }
}
```

### Process and Task Management
- **Use `withCheckedThrowingContinuation` for callback-based APIs** - instead of manual continuation management
- **Always resume continuations exactly once** - use defer or proper control flow
- **Handle cancellation properly** - check `Task.isCancelled` in long-running operations
- **Use structured concurrency** - prefer `TaskGroup` over manual task management

### Main Actor Isolation
- **Mark `@MainActor` for UI-related code** - especially view models and UI updates
- **Use `nonisolated` judiciously** - only when you're certain about thread safety
- **Avoid main actor isolation violations** - don't call main-actor-isolated methods from non-isolated contexts without proper handling

### Common Pitfalls to Avoid

1. **Mutable state capture in closures**
   ```swift
   // ❌ Bad
   var isFinished = false
   handler = {
       isFinished = true // Error: mutation of captured var
   }
   
   // ✅ Good
   let lock = NSLock()
   var isFinished = false
   handler = {
       lock.lock()
       isFinished = true
       lock.unlock()
   }
   ```

2. **Non-Sendable type capture**
   ```swift
   // ❌ Bad
   let fileHandle = FileHandle() // Not Sendable
   Task {
       fileHandle.readData() // Error: capture of non-Sendable type
   }
   
   // ✅ Good
   let data = try await Task {
       try FileHandle(forReadingFrom: url).readToEnd() ?? Data()
   }
   ```

3. **Missing await in async contexts**
   ```swift
   // ❌ Bad
   let result = try run(arguments: ["--cellar"]) // Error: expression is 'async'
   
   // ✅ Good
   let result = try await run(arguments: ["--cellar"])
   ```

## Performance Guidelines

### Memory Management
- Use `@Observable` classes with `@MainActor` for shared state management
- Avoid creating unnecessary view hierarchies - prefer lightweight `View` structs
- Use `ForEach` with proper `id` parameters to avoid unnecessary view recreation
- Prefer `LazyVStack` and `LazyHStack` for large lists over regular `VStack`/`HStack`

### File Operations
- Use modern URL APIs for all file system operations
- Implement proper error handling instead of silent failures with `try?`
- Use background queues for file I/O operations when appropriate
- Cache frequently accessed file system information

### String Processing
- Prefer Swift-native string methods over Foundation equivalents
- Use `localizedStandardContains()` for user-facing search functionality
- Avoid expensive string operations in view body computations
- Use `Text` formatting APIs instead of string interpolation for numeric values

### View Performance
- Keep function bodies under 50 lines for better compilation performance
- Extract complex view logic into separate `View` structs
- Use `.id()` modifier strategically to help SwiftUI with view identity
- Avoid `AnyView` unless absolutely necessary - it defeats SwiftUI's type system optimizations

## SwiftData instructions

If SwiftData is configured to use CloudKit:

- Never use `@Attribute(.unique)`.
- Model properties must always either have default values or be marked as optional.
- All relationships must be marked optional.

## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- **Write unit tests using the modern Swift Testing framework** (introduced in Xcode 16 / Swift 6). Use `@Test` and `#expect` / `#require` instead of XCTestCase and XCTAssert functions.
- Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.

## Development commands

Run these commands from the project root to ensure code quality:

```bash
# Apply auto-fixable linting issues
swiftlint --fix

# Apply code formatting (using Apple's official swift-format)
xcrun swift-format format --in-place --recursive --configuration .swift-format .

# Run linting and formatting checks (should pass with no output/issues)
swiftlint --strict
xcrun swift-format lint --recursive --configuration .swift-format .

# Check for Swift 6 concurrency issues
swiftc -typecheck -swift-version 6 -strict-concurrency=complete Sources/**/*.swift

# Find potential concurrency issues with ast-grep
ast-grep --lang swift -p 'NSMutableData()' # Find non-Sendable types
ast-grep --lang swift -p 'var $VAR = false; $CLOSURE { $VAR = true }' # Mutable captures
ast-grep --lang swift -p '@Sendable { $CAPTURE in $BODY }' # Sendable closure issues

# Run all tests (using modern Swift Testing framework)
swift test
```

## Common Patterns and Examples

### String Manipulation
```swift
// ✅ Good - Swift-native
let cleaned = text.replacing("\n", with: " ")

// ❌ Bad - Foundation method
let cleaned = text.replacingOccurrences(of: "\n", with: " ")
```

### URL Handling
```swift
// ✅ Good - Modern URL API
let homeDir = URL.homeDirectory
let fileURL = homeDir.appending(path: "Documents/file.txt")

// ❌ Bad - String manipulation
let homeDir = NSHomeDirectory()
let fileURL = URL(fileURLWithPath: homeDir + "/Documents/file.txt")
```

### Error Handling
```swift
// ✅ Good - Proper error handling
do {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
} catch {
    print("Error creating directory: \(error)")
    lastError = "Failed to create directory: \(error.localizedDescription)"
}

// ❌ Bad - Silent failure
// try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
```

### SwiftUI Color Usage
```swift
// ✅ Good - SwiftUI-native or properly wrapped
.background(Color(NSColor.windowBackgroundColor))
.foregroundStyle(.secondary)

// ❌ Bad - Invalid SwiftUI properties
.background(Color.windowBackground)  // Doesn't exist
.background(Color.controlBackground)  // Doesn't exist
```

### Function Body Length
Keep functions focused and under 50 lines. Break complex operations into smaller, well-named helper methods:

```swift
// ✅ Good - Refactored into focused methods
func saveSnippet(_ snippet: Snippet) {
    let baseDirectory = determineBaseDirectory(for: snippet)
    ensureDirectoryExists(baseDirectory)
    let content = createFrontmatterString(for: snippet)
    writeContent(content, to: baseDirectory)
    updateSnippetInMemory(snippet)
}
```
