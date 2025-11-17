#!/usr/bin/env bash

################################################################################
# Create Hand-Picked Release PR
#
# Creates a release pull request that merges only selected PRs from `develop`
# branch into `master` (or `main`) branch. This is useful when you don't want
# to merge all changes from develop, but only specific PRs.
#
# Automatically detects the repository from the current git directory.
#
# Usage:
#   .script.sh                    # Interactive mode
#   .script.sh [PR_NUMBERS...]    # Direct mode with PR numbers/commit hashes
#   .script.sh --help             # Show help message
#
# Examples:
#   .script.sh 1234 1235 1236
#   .script.sh 1234 abc1234 1235
################################################################################

set -e

# Script metadata
SCRIPT_NAME="create-handpicked-release-PR"
SCRIPT_VERSION="1.0.0"

# Constants
MAX_PR_LIMIT=200
TITLE_MAX_LENGTH=35
COMMIT_HASH_MIN_LENGTH=7

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display help message
show_help() {
    printf "${CYAN}Create Hand-Picked Release PR${NC}\n"
    printf "\n"
    printf "Creates a release pull request that merges only selected PRs from \`develop\` branch\n"
    printf "into \`master\` (or \`main\`) branch. Automatically detects the repository from\n"
    printf "the current git directory.\n"
    printf "\n"
    printf "${GREEN}Usage:${NC}\n"
    printf "  .script.sh                    # Interactive mode (recommended)\n"
    printf "  .script.sh [PR_NUMBERS...]    # Direct mode with PR numbers/commit hashes\n"
    printf "  .script.sh --help             # Show this help message\n"
    printf "\n"
    printf "${GREEN}Examples:${NC}\n"
    printf "  .script.sh                    # Interactive selection\n"
    printf "  .script.sh 1234 1235 1236     # Include specific PRs\n"
    printf "  .script.sh 1234 abc1234 1235  # Mix of PRs and commits\n"
    printf "\n"
    printf "${GREEN}Requirements:${NC}\n"
    printf "  - GitHub CLI (\`gh\`) must be installed and authenticated\n"
    printf "  - Must be run from within a git repository\n"
    printf "  - Must have write access to the repository\n"
    printf "  - Repository must have \`develop\` and \`master\`/\`main\` branches\n"
    printf "  - Selected PRs must be merged to \`develop\` branch\n"
    printf "\n"
    printf "${GREEN}What it does:${NC}\n"
    printf "  1. Auto-detects repository from current git directory\n"
    printf "  2. Finds differences between master/main and develop\n"
    printf "  3. Shows only unreleased PRs and commits (in interactive mode)\n"
    printf "  4. Validates selected PRs and commits\n"
    printf "  5. Creates a new branch from master/main\n"
    printf "  6. Cherry-picks selected changes\n"
    printf "  7. Prompts for PR settings (draft status and reviewers)\n"
    printf "  8. Creates PR as draft by default (can be changed to active)\n"
    printf "  9. Creates a PR with formatted description\n"
    printf "\n"
}

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Get PR numbers from arguments
PR_NUMBERS=("$@")

################################################################################
# Initialization & Validation
################################################################################

# Auto-detect repository from current git directory
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Must be run from within a git repository${NC}"
    exit 1
fi

REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [[ -z "$REPO_FULL" ]]; then
    echo -e "${RED}❌ Error: Could not detect repository. Make sure you're in a git repository with GitHub remote${NC}"
    exit 1
fi

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) is not installed. Please install it first:${NC}"
    echo "   brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}❌ Not authenticated with GitHub CLI. Please run:${NC}"
    echo "   gh auth login"
    exit 1
fi

################################################################################
# Interactive Mode: Find and Display Unreleased Changes
################################################################################

if [[ ${#PR_NUMBERS[@]} -eq 0 ]]; then
    echo -e "${BLUE}🚀 Creating hand-picked release PR for ${REPO_FULL}${NC}\n"
    echo -e "${CYAN}📋 Interactive Mode: Let's find PRs to include${NC}\n"
    
    # Fetch latest changes
    echo -e "${BLUE}📥 Fetching latest changes from develop and master...${NC}\n"
    
    # Determine master branch name using GitHub API
    MASTER_BRANCH="master"
    if ! gh api "repos/${REPO_FULL}/branches/master" --jq .name > /dev/null 2>&1; then
        if gh api "repos/${REPO_FULL}/branches/main" --jq .name > /dev/null 2>&1; then
            MASTER_BRANCH="main"
        fi
    fi
    
    # Fetch latest changes (optional, but helpful for git operations)
    git fetch origin develop "${MASTER_BRANCH}" 2>/dev/null || true
    
    # Find the differences between master and develop using GitHub API
    echo -e "${BLUE}🔍 Finding differences between ${MASTER_BRANCH} and develop...${NC}\n"
    
    # Get commits that are in develop but not in master using GitHub API
    UNRELEASED_COMMIT_LIST=$(gh api "repos/${REPO_FULL}/compare/${MASTER_BRANCH}...develop" --jq '.commits[] | .sha' 2>/dev/null || echo "")
    
    # If GitHub API fails, try git as fallback
    if [[ -z "$UNRELEASED_COMMIT_LIST" ]]; then
        UNRELEASED_COMMIT_LIST=$(git log "origin/develop" --not "origin/${MASTER_BRANCH}" --oneline --format="%H" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$UNRELEASED_COMMIT_LIST" ]]; then
        echo -e "${GREEN}✅ No unreleased changes found!${NC}"
        echo -e "${GREEN}   All changes in develop have already been merged to ${MASTER_BRANCH}${NC}\n"
        exit 0
    fi
    
    # Get all merged PRs from develop
    ALL_MERGED_PRS=$(gh pr list --repo "${REPO_FULL}" --base develop --state merged --limit ${MAX_PR_LIMIT} --json number,title,mergedAt,author,mergeCommit --jq '.[] | "PR|\(.number)|\(.title)|\(.mergedAt)|\(.author.login)|\(.mergeCommit.oid // "")"' 2>/dev/null || echo "")
    
    # Filter PRs to only include those whose merge commits are in the unreleased commit list
    MERGED_PRS=""
    if [[ -n "$ALL_MERGED_PRS" ]]; then
        while IFS='|' read -r type number title merged_at author commit_hash; do
            if [[ "$type" == "PR" ]]; then
                # Check if this PR's merge commit is in the unreleased commits
                if [[ -n "$commit_hash" && "$commit_hash" != "null" ]]; then
                    # Check if this commit is in the unreleased list
                    if echo "$UNRELEASED_COMMIT_LIST" | grep -q "^${commit_hash}$"; then
                        MERGED_PRS+="PR|${number}|${title}|${merged_at}|${author}|${commit_hash}"$'\n'
                    fi
                else
                    # Try to find merge commit by PR number in unreleased commits
                    PR_MERGE_COMMIT=$(git log --grep="#${number}" --oneline "origin/develop" --not "origin/${MASTER_BRANCH}" --format="%H" | head -1 || echo "")
                    if [[ -n "$PR_MERGE_COMMIT" ]]; then
                        MERGED_PRS+="PR|${number}|${title}|${merged_at}|${author}|${PR_MERGE_COMMIT}"$'\n'
                    fi
                fi
            fi
        done <<< "$ALL_MERGED_PRS"
    fi
    
    # Get commits in develop that are not in master (waiting to be released)
    echo -e "${BLUE}🔍 Analyzing commits waiting to be released...${NC}\n"
    
    # Get merge commits from PRs we found
    PR_MERGE_COMMITS=$(echo "$MERGED_PRS" | grep -E "^PR\|" | cut -d'|' -f6 | grep -v "^$" || echo "")
    
    # Get all commits in develop but not in master using GitHub API
    # Get all commits (including merge commits) to see the full picture
    # Also try to get PR numbers from the commit URL or associated PRs
    ALL_UNRELEASED_COMMITS=$(gh api "repos/${REPO_FULL}/compare/${MASTER_BRANCH}...develop" --jq '.commits[] | select(.parents | length == 1) | "\(.sha)|\(.commit.message | split("\n")[0])|\(.commit.author.name)|\(.commit.author.date | split("T")[0])|\(.url)"' 2>/dev/null || echo "")
    
    # If GitHub API fails, try git as fallback
    if [[ -z "$ALL_UNRELEASED_COMMITS" ]]; then
        ALL_UNRELEASED_COMMITS=$(git log "origin/develop" --not "origin/${MASTER_BRANCH}" --oneline --no-merges --format="%H|%s|%an|%ad" --date=short 2>/dev/null || echo "")
    fi
    
    # Filter out commits that are part of PR merges (they're already included as PRs)
    # Use GitHub API to check if commits are part of PRs
    DIRECT_COMMITS=""
    if [[ -n "$ALL_UNRELEASED_COMMITS" ]]; then
        while IFS='|' read -r hash subject author date commit_url; do
            # Check if this commit is part of any PR we found
            IS_PR_COMMIT=false
            
            # Check if this commit hash matches any PR merge commit
            if [[ -n "$PR_MERGE_COMMITS" ]]; then
                for PR_MERGE in $PR_MERGE_COMMITS; do
                    if [[ -n "$PR_MERGE" && "$hash" == "$PR_MERGE" ]]; then
                        IS_PR_COMMIT=true
                        break
                    fi
                done
            fi
            
            # Check if this commit is associated with any PR (using GitHub API)
            # This gives us the PR number for display, even if we show the commit separately
            PR_ASSOCIATED=""
            if [[ "$IS_PR_COMMIT" == "false" ]]; then
                # Check if this commit is associated with any PR
                # Use a timeout to avoid hanging on slow API calls (macOS doesn't have timeout, use alternative)
                # Try to get PR number, but don't let it block (use background process or quick check)
                PR_ASSOCIATED=$(gh api "repos/${REPO_FULL}/commits/${hash}/pulls" --jq '.[0].number // empty' 2>/dev/null || echo "")
            fi
            
            # Include the commit (even if it's from a PR, show it with PR number like the UI)
            if [[ "$IS_PR_COMMIT" == "false" ]]; then
                # Add PR number at the start of the title if available
                if [[ -n "$PR_ASSOCIATED" ]]; then
                    DIRECT_COMMITS+="COMMIT|${hash}|PR #${PR_ASSOCIATED}: ${subject}|${date}|${author}"$'\n'
                else
                    DIRECT_COMMITS+="COMMIT|${hash}|${subject}|${date}|${author}"$'\n'
                fi
            fi
        done <<< "$ALL_UNRELEASED_COMMITS"
    fi
    
    # Combine PRs and direct commits, sort by date
    ALL_CHANGES=""
    if [[ -n "$MERGED_PRS" ]]; then
        ALL_CHANGES+="$MERGED_PRS"$'\n'
    fi
    if [[ -n "$DIRECT_COMMITS" ]]; then
        ALL_CHANGES+="$DIRECT_COMMITS"
    fi
    
    if [[ -z "$ALL_CHANGES" ]]; then
            echo -e "${GREEN}✅ No unreleased changes found!${NC}"
            echo -e "${GREEN}   All changes in develop have already been merged to ${MASTER_BRANCH}${NC}\n"
            echo -e "${YELLOW}   You can manually specify PR numbers or commit hashes if needed:${NC}"
            echo -e "${CYAN}   .script.sh PR1 PR2 COMMIT_HASH${NC}"
            exit 0
    fi
    
    echo -e "${GREEN}Changes waiting to be released (in develop, not in ${MASTER_BRANCH}):${NC}\n"
    echo -e "${CYAN}Type  ID/Ref                                    Title/Subject                    Author    Date${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    # Use regular arrays instead of associative arrays for compatibility
    CHANGE_ITEMS=()
    INDEX=1
    
    # Sort by date (newest first) - simple approach: show PRs first, then commits
    if [[ -n "$MERGED_PRS" ]]; then
        while IFS='|' read -r type number title merged_at author commit_hash; do
            if [[ "$type" == "PR" ]]; then
                # Format merged date
                MERGED_DATE=$(echo "$merged_at" | cut -d'T' -f1)
                # Truncate title if too long
                TITLE_SHORT=$(echo "$title" | cut -c1-${TITLE_MAX_LENGTH})
                if [[ ${#title} -gt ${TITLE_MAX_LENGTH} ]]; then
                    TITLE_SHORT="${TITLE_SHORT}..."
                fi
                printf "${GREEN}PR${NC}   ${GREEN}#%-6s${NC}  %-35s  %-10s  %s\n" "$number" "$TITLE_SHORT" "$author" "$MERGED_DATE"
                CHANGE_ITEMS+=("PR|${number}")
                ((INDEX++))
            fi
        done <<< "$MERGED_PRS"
    fi
    
    if [[ -n "$DIRECT_COMMITS" ]]; then
        while IFS='|' read -r type hash subject date author; do
            if [[ "$type" == "COMMIT" ]]; then
                # Truncate subject if too long
                SUBJECT_SHORT=$(echo "$subject" | cut -c1-${TITLE_MAX_LENGTH})
                if [[ ${#subject} -gt ${TITLE_MAX_LENGTH} ]]; then
                    SUBJECT_SHORT="${SUBJECT_SHORT}..."
                fi
                HASH_SHORT=$(echo "$hash" | cut -c1-${COMMIT_HASH_MIN_LENGTH})
                printf "${YELLOW}COMMIT${NC} ${YELLOW}%-6s${NC}  %-35s  %-10s  %s\n" "$HASH_SHORT" "$SUBJECT_SHORT" "$author" "$date"
                CHANGE_ITEMS+=("COMMIT|${hash}")
                ((INDEX++))
            fi
        done <<< "$DIRECT_COMMITS"
    fi
    
    echo ""
    echo -e "${CYAN}Enter PR numbers or commit hashes to include (space-separated):${NC}"
    echo -e "${YELLOW}  - For PRs: use PR number (e.g., 1234)${NC}"
    echo -e "${YELLOW}  - For commits: use commit hash (e.g., abc1234)${NC}"
    echo -e "${YELLOW}  - Or press Enter to exit${NC}"
    read -p "Selection: " SELECTED
    
    if [[ -z "$SELECTED" ]]; then
        echo -e "${BLUE}ℹ️  Exiting. No PRs selected.${NC}"
        exit 0
    fi
    
    # Parse selected PR numbers
    PR_NUMBERS=($SELECTED)
fi

# Validate we have PR numbers (if not in interactive mode)
if [[ ${#PR_NUMBERS[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No PR numbers provided${NC}"
    echo -e "${YELLOW}Usage: .script.sh [PR1 PR2 PR3]${NC}"
    echo -e "${YELLOW}   Or run without arguments for interactive mode${NC}"
    echo -e "${YELLOW}   Or run with --help to see full documentation${NC}"
    exit 1
fi

################################################################################
# Process Selected PRs and Commits
################################################################################

echo -e "${BLUE}🚀 Creating hand-picked release PR for ${REPO_FULL}${NC}\n"

# Separate PRs and commits from selection
SELECTED_PRS=()
SELECTED_COMMITS=()

for item in "${PR_NUMBERS[@]}"; do
    # Check if it's a commit hash (alphanumeric, 7+ chars) or PR number (numeric)
    if [[ "$item" =~ ^[0-9]+$ ]]; then
        SELECTED_PRS+=("$item")
    elif [[ "$item" =~ ^[a-f0-9]{7,}$ ]]; then
        SELECTED_COMMITS+=("$item")
    else
        # Try to find full commit hash from short hash
        FULL_HASH=$(git rev-parse --verify "$item" 2>/dev/null || echo "")
        if [[ -n "$FULL_HASH" ]]; then
            SELECTED_COMMITS+=("$FULL_HASH")
        else
            echo -e "${YELLOW}⚠️  Warning: '${item}' is not a valid PR number or commit hash, skipping${NC}"
        fi
    fi
done

# Get current date in "Mon DD" format
RELEASE_DATE=$(date +"%b %d")
BRANCH_NAME="release/handpicked-$(date +%Y%m%d-%H%M%S)"
 PR_TITLE="Release, ${RELEASE_DATE} (Hand-picked)"

echo -e "${GREEN}📅 Release date: ${RELEASE_DATE}${NC}"
echo -e "${GREEN}📝 PR title: ${PR_TITLE}${NC}"
echo -e "${GREEN}🌿 Branch name: ${BRANCH_NAME}${NC}"

if [[ ${#SELECTED_PRS[@]} -gt 0 ]]; then
    echo -e "${GREEN}📦 Selected PRs: ${SELECTED_PRS[*]}${NC}"
fi
if [[ ${#SELECTED_COMMITS[@]} -gt 0 ]]; then
    echo -e "${GREEN}📝 Selected Commits: ${SELECTED_COMMITS[*]}${NC}"
fi
echo ""

# Determine master branch name
MASTER_BRANCH="master"
if ! git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
    if git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
        MASTER_BRANCH="main"
    fi
fi

echo -e "${BLUE}📥 Fetching latest changes...${NC}"
git fetch origin develop "${MASTER_BRANCH}" 2>/dev/null || true

# Check current branch and stash if needed
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
HAS_CHANGES=$(git status --porcelain)

if [[ -n "$HAS_CHANGES" ]]; then
    echo -e "${YELLOW}⚠️  You have uncommitted changes.${NC}"
    read -p "Stash them and continue? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git stash push -m "Stashed for hand-picked release PR"
        STASHED=true
    else
        echo -e "${RED}❌ Please commit or stash your changes first${NC}"
        exit 1
    fi
else
    STASHED=false
fi

# Create new branch from master
echo -e "${BLUE}🌿 Creating branch ${BRANCH_NAME} from ${MASTER_BRANCH}...${NC}"
git checkout -b "${BRANCH_NAME}" "origin/${MASTER_BRANCH}" 2>/dev/null || git checkout -b "${BRANCH_NAME}" "${MASTER_BRANCH}"

################################################################################
# Validate PRs and Commits
################################################################################

# Validate and get PR merge commits
echo -e "${BLUE}🔍 Validating PRs and commits...${NC}\n"
PR_MERGE_COMMITS=()
PR_TITLES=()
COMMIT_HASHES=()
COMMIT_TITLES=()
FAILED_ITEMS=()

# Process PRs
for PR_NUM in "${SELECTED_PRS[@]}"; do
    # Validate PR exists and is merged to develop
    PR_INFO=$(gh pr view "${PR_NUM}" --repo "${REPO_FULL}" --json number,title,state,baseRefName,mergedAt,mergeCommit 2>/dev/null || echo "")
    
    if [[ -z "$PR_INFO" ]]; then
        echo -e "${RED}❌ PR #${PR_NUM} not found${NC}"
        FAILED_ITEMS+=("PR #${PR_NUM}")
        continue
    fi
    
    PR_STATE=$(echo "$PR_INFO" | jq -r '.state')
    PR_BASE=$(echo "$PR_INFO" | jq -r '.baseRefName')
    PR_MERGED_AT=$(echo "$PR_INFO" | jq -r '.mergedAt')
    CURRENT_PR_TITLE=$(echo "$PR_INFO" | jq -r '.title')
    MERGE_COMMIT=$(echo "$PR_INFO" | jq -r '.mergeCommit.oid // empty')
    
    if [[ "$PR_STATE" != "MERGED" ]]; then
        echo -e "${YELLOW}⚠️  PR #${PR_NUM} is not merged (state: ${PR_STATE})${NC}"
        FAILED_ITEMS+=("PR #${PR_NUM}")
        continue
    fi
    
    if [[ "$PR_BASE" != "develop" ]]; then
        echo -e "${YELLOW}⚠️  PR #${PR_NUM} was not merged to develop (base: ${PR_BASE})${NC}"
        FAILED_ITEMS+=("PR #${PR_NUM}")
        continue
    fi
    
    if [[ -z "$PR_MERGED_AT" || "$PR_MERGED_AT" == "null" ]]; then
        echo -e "${YELLOW}⚠️  PR #${PR_NUM} merge commit not found${NC}"
        FAILED_ITEMS+=("PR #${PR_NUM}")
        continue
    fi
    
    # Try to find merge commit if not directly available
    if [[ -z "$MERGE_COMMIT" || "$MERGE_COMMIT" == "null" ]]; then
        # Get the merge commit from develop that contains this PR
        MERGE_COMMIT=$(git log --grep="#${PR_NUM}" --oneline origin/develop | head -1 | cut -d' ' -f1 || echo "")
        if [[ -z "$MERGE_COMMIT" ]]; then
            echo -e "${YELLOW}⚠️  Could not find merge commit for PR #${PR_NUM}${NC}"
            FAILED_ITEMS+=("PR #${PR_NUM}")
            continue
        fi
    fi
    
    echo -e "${GREEN}✅ PR #${PR_NUM}: ${CURRENT_PR_TITLE}${NC}"
    PR_MERGE_COMMITS+=("${MERGE_COMMIT}")
    PR_TITLES+=("#${PR_NUM}: ${CURRENT_PR_TITLE}")
done

# Process commits
for COMMIT_HASH in "${SELECTED_COMMITS[@]}"; do
    # Validate commit exists on develop
    if ! git cat-file -e "${COMMIT_HASH}" 2>/dev/null; then
        # Try to fetch it
        git fetch origin "${COMMIT_HASH}" 2>/dev/null || true
    fi
    
    # Check if commit is on develop
    if ! git branch -r --contains "${COMMIT_HASH}" 2>/dev/null | grep -q "origin/develop"; then
        echo -e "${YELLOW}⚠️  Commit ${COMMIT_HASH:0:${COMMIT_HASH_MIN_LENGTH}} is not on develop branch${NC}"
        FAILED_ITEMS+=("Commit ${COMMIT_HASH:0:${COMMIT_HASH_MIN_LENGTH}}")
        continue
    fi
    
    # Get commit info
    COMMIT_SUBJECT=$(git log -1 --format="%s" "${COMMIT_HASH}" 2>/dev/null || echo "Unknown")
    COMMIT_AUTHOR=$(git log -1 --format="%an" "${COMMIT_HASH}" 2>/dev/null || echo "Unknown")
    
    echo -e "${GREEN}✅ Commit ${COMMIT_HASH:0:${COMMIT_HASH_MIN_LENGTH}}: ${COMMIT_SUBJECT}${NC}"
    COMMIT_HASHES+=("${COMMIT_HASH}")
    COMMIT_TITLES+=("Commit ${COMMIT_HASH:0:${COMMIT_HASH_MIN_LENGTH}}: ${COMMIT_SUBJECT}")
done

# Check if we have anything to include
TOTAL_ITEMS=$((${#PR_MERGE_COMMITS[@]} + ${#COMMIT_HASHES[@]}))

if [[ $TOTAL_ITEMS -eq 0 ]]; then
    echo -e "${RED}❌ No valid PRs or commits to include. Aborting.${NC}"
    git checkout "${CURRENT_BRANCH}" 2>/dev/null || true
    if [[ "$STASHED" == "true" ]]; then
        git stash pop 2>/dev/null || true
    fi
    exit 1
fi

if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
    echo -e "\n${YELLOW}⚠️  Some items could not be included: ${FAILED_ITEMS[*]}${NC}"
    read -p "Continue with valid items only? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        git checkout "${CURRENT_BRANCH}" 2>/dev/null || true
        if [[ "$STASHED" == "true" ]]; then
            git stash pop 2>/dev/null || true
        fi
        exit 0
    fi
fi

################################################################################
# Cherry-pick Selected Changes
################################################################################

# Cherry-pick merge commits and regular commits
echo -e "\n${BLUE}🍒 Cherry-picking selected changes...${NC}\n"

# Cherry-pick PRs (merge commits)
for i in "${!PR_MERGE_COMMITS[@]}"; do
    COMMIT="${PR_MERGE_COMMITS[$i]}"
    PR_LABEL="${PR_TITLES[$i]}"
    
    echo -e "${CYAN}Cherry-picking ${PR_LABEL}...${NC}"
    
    if git cherry-pick -m 1 "${COMMIT}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Successfully cherry-picked ${PR_LABEL}${NC}"
    else
        echo -e "${RED}❌ Failed to cherry-pick ${PR_LABEL}${NC}"
        echo -e "${YELLOW}   You may need to resolve conflicts manually${NC}"
        read -p "Continue with remaining items? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            git cherry-pick --abort 2>/dev/null || true
            git checkout "${CURRENT_BRANCH}" 2>/dev/null || true
            if [[ "$STASHED" == "true" ]]; then
                git stash pop 2>/dev/null || true
            fi
            exit 1
        fi
    fi
done

# Cherry-pick regular commits
for i in "${!COMMIT_HASHES[@]}"; do
    COMMIT="${COMMIT_HASHES[$i]}"
    COMMIT_TITLE="${COMMIT_TITLES[$i]}"
    
    echo -e "${CYAN}Cherry-picking ${COMMIT_TITLE}...${NC}"
    
    if git cherry-pick "${COMMIT}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Successfully cherry-picked ${COMMIT_TITLE}${NC}"
    else
        echo -e "${RED}❌ Failed to cherry-pick ${COMMIT_TITLE}${NC}"
        echo -e "${YELLOW}   You may need to resolve conflicts manually${NC}"
        read -p "Continue with remaining items? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            git cherry-pick --abort 2>/dev/null || true
            git checkout "${CURRENT_BRANCH}" 2>/dev/null || true
            if [[ "$STASHED" == "true" ]]; then
                git stash pop 2>/dev/null || true
            fi
            exit 1
        fi
    fi
done

################################################################################
# Create Pull Request
################################################################################

# Push branch
echo -e "\n${BLUE}📤 Pushing branch to origin...${NC}"
git push -u origin "${BRANCH_NAME}" 2>&1 | grep -v "remote:" || true

# Create PR body with formatted description
printf -v PR_BODY "Hand-picked release PR merging selected PRs and commits from develop into %s for %s.

This PR was created using the \`%s\` script.

" "${MASTER_BRANCH}" "${RELEASE_DATE}" "${SCRIPT_NAME}"

if [[ ${#PR_TITLES[@]} -gt 0 ]]; then
    printf -v SECTION "## Included PRs:

"
    PR_BODY+="$SECTION"
    for PR_LABEL in "${PR_TITLES[@]}"; do
        printf -v LINE "- %s\n" "${PR_LABEL}"
        PR_BODY+="$LINE"
    done
    PR_BODY+=$'\n'
fi

if [[ ${#COMMIT_TITLES[@]} -gt 0 ]]; then
    printf -v SECTION "## Included Commits:

"
    PR_BODY+="$SECTION"
    for COMMIT_TITLE in "${COMMIT_TITLES[@]}"; do
        printf -v LINE "- %s\n" "${COMMIT_TITLE}"
        PR_BODY+="$LINE"
    done
    PR_BODY+=$'\n'
fi

if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
    printf -v SECTION "## Skipped Items (could not be included):

"
    PR_BODY+="$SECTION"
    for FAILED_ITEM in "${FAILED_ITEMS[@]}"; do
        printf -v LINE "- %s\n" "${FAILED_ITEM}"
        PR_BODY+="$LINE"
    done
    PR_BODY+=$'\n'
fi

# Ask if user wants to create as draft (default: yes)
echo -e "\n${CYAN}📝 PR Settings:${NC}"
read -p "Create PR as draft? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    CREATE_DRAFT=false
    echo -e "${GREEN}✓ Will create as active PR${NC}"
else
    CREATE_DRAFT=true
    echo -e "${GREEN}✓ Will create as draft PR${NC}"
fi

# Ask for reviewers (optional)
echo ""
read -p "Add reviewers? (space-separated GitHub usernames, or press Enter to skip): " REVIEWERS_INPUT

# Store reviewers for PR body
REVIEWERS_FOR_BODY=""
if [[ -n "$REVIEWERS_INPUT" ]]; then
    echo -e "${GREEN}✓ Reviewers: ${REVIEWERS_INPUT}${NC}"
    REVIEWERS_FOR_BODY="$REVIEWERS_INPUT"
    # Add reviewers info to PR body
    printf -v REVIEWERS_SECTION "## Reviewers:

- %s

" "${REVIEWERS_FOR_BODY}"
    PR_BODY+="$REVIEWERS_SECTION"
else
    echo -e "${BLUE}ℹ️  No reviewers specified${NC}"
fi

# Create the PR
echo -e "\n${BLUE}🔨 Creating PR...${NC}"

# Build the gh pr create command with proper argument handling
PR_CMD_ARGS=(
    "pr" "create"
    "--base" "${MASTER_BRANCH}"
    "--head" "${BRANCH_NAME}"
    "--title" "${PR_TITLE}"
    "--body" "${PR_BODY}"
    "--repo" "${REPO_FULL}"
)

# Add draft flag if needed
if [[ "$CREATE_DRAFT" == "true" ]]; then
    PR_CMD_ARGS+=("--draft")
fi

# Add reviewers if specified
if [[ -n "$REVIEWERS_INPUT" ]]; then
    # Split reviewers and add each as a separate --reviewer flag
    for reviewer in $REVIEWERS_INPUT; do
        PR_CMD_ARGS+=("--reviewer" "$reviewer")
    done
fi

# Execute the command and capture both output and exit code
PR_URL=$(gh "${PR_CMD_ARGS[@]}" 2>&1)
PR_EXIT_CODE=$?

if [[ $PR_EXIT_CODE -eq 0 ]]; then
    PR_STATUS=""
    if [[ "$CREATE_DRAFT" == "true" ]]; then
        PR_STATUS=" (draft)"
    fi
    echo -e "${GREEN}✅ Successfully created hand-picked release PR${PR_STATUS}!${NC}"
    echo -e "${GREEN}   ${PR_URL}${NC}\n"
    
    # Restore original branch and stash
    git checkout "${CURRENT_BRANCH}" 2>/dev/null || true
    if [[ "$STASHED" == "true" ]]; then
        git stash pop 2>/dev/null || true
    fi
else
    echo -e "${RED}❌ Error creating PR:${NC}"
    echo "$PR_URL"
    git checkout "${CURRENT_BRANCH}" 2>/dev/null || true
    if [[ "$STASHED" == "true" ]]; then
        git stash pop 2>/dev/null || true
    fi
    exit 1
fi

