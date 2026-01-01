# BrewDeck

BrewDeck is a user-friendly macOS GUI application built with SwiftUI that simplifies the management of Homebrew packages. With BrewDeck, you can easily install, update, and uninstall Brew packages without needing to use the command line.

## Features

- **Install Packages**: Search and install new Homebrew packages directly from the app.
- **Update Packages**: Keep your installed packages up to date with one-click updates.
- **Auto-Update Packages**: Enable automatic updates to keep your packages up-to-date every 24 hours.
- **Uninstall Packages**: Remove unwanted packages effortlessly.
- **Package Details**: View detailed information about packages, including descriptions and versions.
- **Sidebar Navigation**: Intuitive sidebar for easy navigation between package lists, settings, and more.

## Requirements

- macOS 12.0 or later
- Xcode 14.0 or later (for building the project)
- Homebrew installed on your system (visit [brew.sh](https://brew.sh/) to install)

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/BrewDeck.git
   ```

2. Open the project in Xcode:
   ```
   cd BrewDeck
   open BrewDeck.xcodeproj
   ```

3. Build and run the application using Xcode.

## Usage

1. Launch BrewDeck after building.
2. Use the sidebar to navigate to different sections:
   - **Package List**: Browse and manage installed packages.
   - **Settings**: Configure app preferences.
3. To install a package:
   - Search for the package name.
   - Click "Install".
4. To update or uninstall:
   - Select a package from the list.
   - Use the available actions.

### Auto-Update Feature

BrewDeck includes an auto-update feature that automatically updates your Homebrew packages every 24 hours:

1. Navigate to **Settings** in the sidebar.
2. Enable the **"Auto-update packages"** toggle.
3. Once enabled, BrewDeck will:
   - Check for outdated packages every 24 hours
   - Automatically update any outdated packages
   - Display update progress in the operation logs
   - Show the last auto-update time in the status

The auto-update setting persists across app restarts, so you only need to enable it once. You can disable it at any time by turning off the toggle in Settings.

**Note**: The auto-update feature requires the app to be running. If you close BrewDeck, auto-update will pause and resume when you launch the app again.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Disclaimer

BrewDeck is not affiliated with Homebrew. Use at your own risk.