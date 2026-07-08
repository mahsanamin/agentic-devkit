#!/bin/bash
# a_c_uninstall_app.sh: uninstall a macOS app and its leftover Library files
# (Preferences, Application Support, Caches, Logs, Saved Application State).
#
# Usage:
#   a_c_uninstall_app.sh <app-name-or-path> [--delete]
#
# Argument (required):
#   <app-name-or-path>   app name (e.g. "Slack") or full path to the .app.
#
# Options:
#   --delete     actually remove the app and its files (asks to confirm first).
#                [default: OFF = dry run, only prints what WOULD be deleted]
#   -h, --help   show this help
#
# Default is a safe DRY RUN: nothing is deleted unless you pass --delete.
#
# Examples:
#   a_c_uninstall_app.sh Slack             # dry run: list what would be removed
#   a_c_uninstall_app.sh Slack --delete    # actually uninstall (confirms first)

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

# Flag to determine whether we should delete or run in debug (dry run) mode
DELETE_MODE=false

# Define colors
RED='\033[31m'
BLUE='\033[34m'
RESET='\033[0m'

# Parse command-line options for the --delete flag
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --delete) DELETE_MODE=true ;;  # Set delete mode if --delete flag is passed
        -h|--help) usage; exit 0 ;;
        *) APP_NAME="$1" ;;  # Capture the app name or path
    esac
    shift
done

# Function to count files in a directory or path, excluding system directories
count_files_with_exclusions() {
    local search_path="$1"
    local search_name="$2"

    # Exclude system directories (e.g., anything starting with 'com.apple')
    find "$search_path" -type f -iname "*$search_name*" ! -path "*/com.apple/*" ! -path "*/CloudDocs/*" ! -path "*/System/*" 2>/dev/null | wc -l
}

# Function to remove an app and its related files
uninstall_app() {
    APP_PATH="$1"
    APP_NAME=$(basename "$APP_PATH" .app)

    echo "DEBUG: App Path: $APP_PATH"
    echo "DEBUG: App Name: $APP_NAME"

    # Check if the app exists in /Applications folder
    if [ ! -d "$APP_PATH" ]; then
        echo -e "${RED}Warning: App $APP_NAME not found at the specified path: $APP_PATH. Continuing to delete supporting files...${RESET}"
    fi

    echo "Preparing to uninstall $APP_NAME..."

    if [[ "$DELETE_MODE" == true ]]; then
        # Prompt for confirmation only in delete mode
        read -p "Are you sure you want to uninstall $APP_NAME and its supporting files? (y/n) " CONFIRM
        if [[ "$CONFIRM" != "y" ]]; then
            echo "Uninstallation canceled."
            exit 1
        fi

        echo -e "${RED}Uninstalling $APP_NAME and its supporting files...${RESET}"

        # Remove the app only if it exists
        if [ -d "$APP_PATH" ]; then
            sudo rm -rf "$APP_PATH"
        fi

        # Remove supporting files
        sudo rm -rf ~/Library/Preferences/*"$APP_NAME"*
        sudo rm -rf ~/Library/Application\ Support/*"$APP_NAME"*
        sudo rm -rf ~/Library/Caches/*"$APP_NAME"*
        sudo rm -rf ~/Library/Logs/*"$APP_NAME"*
        sudo rm -rf ~/Library/Saved\ Application\ State/*"$APP_NAME"*.savedState

        echo -e "${RED}$APP_NAME and its supporting files have been completely uninstalled.${RESET}"
    else
        # Debug mode (dry run)
        echo "$APP_NAME would have been uninstalled (dry run)."

        # Show files that would be deleted in blue
        echo -e "${BLUE}Files that would be deleted:${RESET}"
        if [ -d "$APP_PATH" ]; then
            echo -e "${BLUE}  $APP_PATH (Files: $(count_files_with_exclusions /Applications "$APP_NAME"))${RESET}"
        else
            echo -e "${RED}  App $APP_NAME not found in /Applications, only supporting files will be deleted.${RESET}"
        fi
        echo -e "${BLUE}  ~/Library/Preferences/*$APP_NAME* (Files: $(count_files_with_exclusions ~/Library/Preferences "$APP_NAME"))${RESET}"
        echo -e "${BLUE}  ~/Library/Application Support/*$APP_NAME* (Files: $(count_files_with_exclusions ~/Library/Application\ Support "$APP_NAME"))${RESET}"
        echo -e "${BLUE}  ~/Library/Caches/*$APP_NAME* (Files: $(count_files_with_exclusions ~/Library/Caches "$APP_NAME"))${RESET}"
        echo -e "${BLUE}  ~/Library/Logs/*$APP_NAME* (Files: $(count_files_with_exclusions ~/Library/Logs "$APP_NAME"))${RESET}"
        echo -e "${BLUE}  ~/Library/Saved Application State/*$APP_NAME*.savedState (Files: $(count_files_with_exclusions ~/Library/Saved\ Application\ State "$APP_NAME"))${RESET}"
    fi
}

# Function to find the app in /Applications or using mdfind
find_app() {
    APP_NAME="$1"

    # Check in /Applications
    APP_PATH="/Applications/$APP_NAME.app"
    if [ -d "$APP_PATH" ]; then
        echo "$APP_NAME found in /Applications."
        uninstall_app "$APP_PATH"
        return
    fi

    # Use mdfind to locate the app elsewhere, but continue even if not found
    APP_PATH=$(mdfind "kMDItemFSName = '$APP_NAME'" | grep ".app" | head -n 1)
    if [ -z "$APP_PATH" ]; then
        echo "App $APP_NAME not found in /Applications or elsewhere. Proceeding to delete supporting files only."
        APP_PATH="/Applications/$APP_NAME.app"  # Default path to check supporting files
    else
        echo "$APP_NAME found at $APP_PATH."
    fi
    uninstall_app "$APP_PATH"
}

# Check if the user provided an app name or full path
if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <App Name or Full Path> [--delete]"
    exit 1
fi

# Check if the argument is a path or just the app name
if [[ "$APP_NAME" == */* ]]; then
    # If the argument contains a slash, assume it's a path
    uninstall_app "$APP_NAME"
else
    # Otherwise, treat it as an app name and call find_app
    find_app "$APP_NAME"
fi
