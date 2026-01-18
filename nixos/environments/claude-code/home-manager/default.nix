{ pkgs, osConfig, ... }:
{
  home.packages = with pkgs; [
    claude-code

    # Tools commonly used by claude-code
    ripgrep # Fast search (rg)
    fd # Fast find
    git # Version control
    gh # GitHub CLI
    jq # JSON processor
    curl # HTTP client
    wget # File downloader
    tree # Directory listing
    nodejs # For npm/node projects
    python3 # For Python projects
    gnumake # Build tool
    cmake # Build system
    gcc # C/C++ compiler
    nixfmt-rfc-style # Nix formatter

    (pkgs.writeShellScriptBin "claude-screenshot" ''
      # Create screenshots directory
      SCREENSHOT_DIR="/tmp/claude-screenshots"
      mkdir -p "$SCREENSHOT_DIR"

      # Generate filename with date and time
      FILENAME="$(date +%Y%m%d_%H%M%S).png"
      FILEPATH="$SCREENSHOT_DIR/$FILENAME"

      # Select region with spectacle, opens editor after capture
      ${pkgs.kdePackages.spectacle}/bin/spectacle -r -o "$FILEPATH"

      # Check if screenshot was created successfully
      if [ -f "$FILEPATH" ]; then
        # Copy filepath to clipboard
        echo -n "$FILEPATH" | ${pkgs.wl-clipboard}/bin/wl-copy

        # Send notification with preview
        ${pkgs.libnotify}/bin/notify-send \
          --icon="$FILEPATH" \
          "Screenshot saved" \
          "$FILEPATH"
      else
        ${pkgs.libnotify}/bin/notify-send \
          --urgency=critical \
          "Screenshot cancelled" \
          "No screenshot was saved"
      fi
    '')
  ];

  programs.fish = {
    enable = true;
    package = osConfig.programs.fish.package; # use nixos
    shellAliases.clauded = "claude --dangerously-skip-permissions";
  };

  # Remove Claude's self-promotional lines from commit messages.
  #
  # Source: https://github.com/anthropics/claude-code/issues/617#issuecomment-2868275366
  programs.git.hooks.commit-msg = pkgs.writeShellScript "clean-claude-code-self-promote" ''
    COMMIT_MSG_FILE=$1

    # Temporary file for processing
    TMP_PROCESSED_MSG_FILE="''${COMMIT_MSG_FILE}.processed.$$"

    # --- Step 1: Define substrings to identify lines for removal ---
    # Any line containing these strings will be removed.
    # Ensure this script file is saved with UTF-8 encoding for the emoji.
    SUBSTRING1="🤖 Generated with"
    SUBSTRING2="Co-Authored-By"

    # --- Step 2: Remove lines containing the substrings ---
    # Use grep -vF to remove lines containing the fixed substrings.
    # -v: Invert match (select non-matching lines).
    # -F: Treat PATTERN as a fixed string, not a regular expression.
    # The output of the first grep is piped to the second grep.
    ${pkgs.gnugrep}/bin/grep -vF "$SUBSTRING1" "$COMMIT_MSG_FILE" | grep -vF "$SUBSTRING2" > "$TMP_PROCESSED_MSG_FILE"

    # --- Step 3: Clean up blank lines from the processed message ---
    # This awk script will:
    # - Skip all leading blank lines.
    # - Print a single blank line for any sequence of one or more blank lines
    #   found *after* at least one non-blank line.
    # - Print non-blank lines.
    # - Avoid trailing blank lines (implicitly, as a pending blank line at EOF
    #   won't be printed).
    ${pkgs.gawk}/bin/awk '
        BEGIN {
            content_has_started = 0 # Flag to track if we have seen the first non-blank line
            pending_blank_line = 0  # Flag to indicate a blank line separator should be printed
        }

        NF { # If the line has fields (it is not blank)
            if (!content_has_started) {
                content_has_started = 1 # Mark that content has started
            } else if (pending_blank_line) {
                print "" # Print the pending blank line separator before this non-blank line
            }
            print $0 # Print the current non-blank line
            pending_blank_line = 0 # Reset pending blank line flag
            next
        }

        !NF { # If the line is blank (NF == 0)
            if (content_has_started) {
                pending_blank_line = 1 # Mark that we have encountered a blank line after content has started
            }
        }
    ' "$TMP_PROCESSED_MSG_FILE" > "$COMMIT_MSG_FILE"

    # Clean up the temporary file
    rm -f "$TMP_PROCESSED_MSG_FILE"

    # Exit with 0 to indicate success
    exit 0
  '';
}
