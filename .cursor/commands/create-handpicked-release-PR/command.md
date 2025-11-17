# Create Hand-Picked Release PR

Creates a release pull request that merges only selected PRs from `develop` branch into `master` (or `main`) branch. This is useful when you don't want to merge all changes from develop, but only specific PRs. Automatically detects the repository from the current git directory.

## For AI Agents / Execution Instructions

When this command is invoked, you should:

1. **Locate the script**: The script is located at `.cursor/commands/create-handpicked-release-PR/script.sh`
2. **Check if executable**: Verify the script has execute permissions:
   ```bash
   chmod +x .cursor/commands/create-handpicked-release-PR/script.sh
   ```
   (Note: The script can also be run with `bash script.sh` if not executable)
3. **Run the script**: Execute the script from the repository root:
   ```bash
   bash .cursor/commands/create-handpicked-release-PR/script.sh [arguments]
   ```
   Or if executable:
   ```bash
   .cursor/commands/create-handpicked-release-PR/script.sh [arguments]
   ```
4. **Handle interactive prompts**: The script may prompt for:
   - PR/commit selection (in interactive mode)
   - Draft PR confirmation (default: Y)
   - Reviewer usernames (optional)
   - Conflict resolution (if cherry-picking fails)
5. **Provide inputs programmatically**: For non-interactive execution, pipe inputs:
   ```bash
   echo -e "y\naozisik" | bash .cursor/commands/create-handpicked-release-PR/script.sh 1190 2fe05fa
   ```

**Important**: Always run from the repository root directory. The script will automatically detect the repository and handle git operations.

## Usage

### Interactive Mode (Recommended)

Run this script:

```bash
.script.sh
```

Or from the command directory:

```bash
.cursor/commands/create-handpicked-release-PR/script.sh
```

The script will:

1. Automatically detect the repository from the current git directory
2. Find the differences between master and develop (what's in develop but not in master)
3. Show you only the PRs and commits that are **waiting to be released** (not already in master)
4. Let you select which PRs and/or commits to include
5. Create a new branch from master
6. Cherry-pick the selected PRs and commits
7. Create a PR with those changes

### Direct Mode (Specify PR Numbers)

```bash
# Specify PR numbers directly
.script.sh 1234 1235 1236

# Mix of PRs and commits
.script.sh 1234 abc1234 1235
```

### Help

```bash
# Show help message
.script.sh --help
```

## What it does

1. **Auto-detects repository** from the current git directory using `gh repo view`
2. Validates that GitHub CLI (`gh`) is installed and authenticated
3. **Finds differences between `master`/`main` and `develop`** - only shows PRs and commits that are in develop but NOT yet in master (waiting to be released)
4. Shows unreleased PRs merged to develop AND unreleased direct commits to develop (in interactive mode)
5. Validates that selected PRs are merged to develop and commits exist on develop
6. Creates a new branch from `master`/`main` (e.g., `release/handpicked-20241117-143022`)
7. Cherry-picks the merge commits from selected PRs and regular commits
8. Pushes the branch and creates a PR with title: "Release, [Mon DD] (Hand-picked)" (e.g., "Release, Nov 17 (Hand-picked)")
9. Prompts for PR settings (draft status and reviewers)
10. Creates the PR as a draft by default (can be changed to active)
11. Includes a list of all included PRs and commits in the PR description

## Requirements

- GitHub CLI (`gh`) must be installed
- Must be authenticated with GitHub CLI (`gh auth login`)
- Must be run from within a git repository (automatically detects which repository)
- Must have write access to the repository
- Repository must have `develop` and `master`/`main` branches
- Selected PRs must be merged to `develop` branch

## Example Output

```
🚀 Creating hand-picked release PR for github/bozonet

📋 Interactive Mode: Let's find PRs to include

📥 Fetching latest changes from develop and master...

🔍 Finding differences between master and develop...

🔍 Analyzing commits waiting to be released...

Changes waiting to be released (in develop, not in master):

Type  ID/Ref                                    Title/Subject                    Author    Date
────────────────────────────────────────────────────────────────────────────────────────────────
PR    #1577    Fix user authentication bug            john      2024-11-17
PR    #1576    Add new feature for reports            jane      2024-11-16
COMMIT abc1234 PR #1188: Update config file          admin     2024-11-15
PR    #1575    Update dependencies                     admin     2024-11-14

Enter PR numbers or commit hashes to include (space-separated):
  - For PRs: use PR number (e.g., 1234)
  - For commits: use commit hash (e.g., abc1234)
Selection: 1577 1576 abc1234

📅 Release date: Nov 17
📝 PR title: Release, Nov 17 (Hand-picked)
🌿 Branch name: release/handpicked-20241117-143022
📦 Selected PRs: 1577 1576
📝 Selected Commits: abc1234

📥 Fetching latest changes...
🌿 Creating branch release/handpicked-20241117-143022 from master...
🔍 Validating PRs and commits...

✅ PR #1577: Fix user authentication bug
✅ PR #1576: Add new feature for reports
✅ Commit abc1234: PR #1188: Update config file

🍒 Cherry-picking selected changes...

Cherry-picking #1577: Fix user authentication bug...
✅ Successfully cherry-picked #1577: Fix user authentication bug
Cherry-picking #1576: Add new feature for reports...
✅ Successfully cherry-picked #1576: Add new feature for reports
Cherry-picking Commit abc1234: PR #1188: Update config file...
✅ Successfully cherry-picked Commit abc1234: PR #1188: Update config file

📤 Pushing branch to origin...

📝 PR Settings:
Create PR as draft? (Y/n): y
✓ Will create as draft PR

Add reviewers? (space-separated GitHub usernames, or press Enter to skip): alice bob
✓ Reviewers: alice bob

🔨 Creating PR...

✅ Successfully created hand-picked release PR (draft)!
   https://github.com/bozonet/project/pull/1578
```

## Notes

- **The script automatically detects the repository** from the current git directory - just copy the script to any repository and run it
- **The script only shows changes that are NOT yet in master** - it compares master and develop to find what's waiting to be released
- If all changes are already in master, the script will exit with a success message
- The script will stash any uncommitted changes before creating the branch (with confirmation)
- If cherry-picking fails due to conflicts, you'll be prompted to resolve them manually
- The script validates that PRs are actually merged to develop before including them
- The script validates that commits exist on the develop branch
- PRs that were merged to other branches will be skipped with a warning
- Direct commits (not from PRs) are shown separately and can be selected by their commit hash
- The script filters out commits that are part of PR merges to avoid duplicates
- If a commit is associated with a PR (e.g., squashed PR), the PR number is displayed in the format: `PR #1188: Update link`
- Use `--help` flag to see detailed usage information and examples
- The script supports both `master` and `main` as the release branch (auto-detected)
- **PRs are created as drafts by default** - press 'n' when prompted to create as active PR
- You can optionally specify reviewers when creating the PR (space-separated GitHub usernames)
