#!/usr/bin/env zsh
# git worktree lifecycle helpers
#   gwtc <repo-url> [dir]        clone bare, ready for worktrees
#   gwtb <branch> [base]         add worktree on new branch
#   gwtd <worktree> [-b]         remove worktree, -b also deletes branch

# Clone a repo as bare for use with git worktrees
# Usage: gwt-clone <repo-url> [directory-name]
gwtc() {
  local repo_url="$1"
  local dir_name="${2:-$(basename "$repo_url" .git)}"
  local default_branch

  if [[ -z "$repo_url" ]]; then
    echo "Usage: gwt-clone <repo-url> [directory-name]"
    return 1
  fi

  mkdir -p "$dir_name" && cd "$dir_name" || return 1

  git clone --bare "$repo_url" .bare
  echo "gitdir: ./.bare" > .git

  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git fetch origin

  # Bare clone copies all remote branches as local branches under refs/heads.
  # Remove them so only worktree-created branches exist locally.
  # Detect the default branch first so we can preserve it.
  default_branch=$(git remote show origin | sed -n 's/.*HEAD branch: //p')
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  # Delete all local branches except the default branch
  git for-each-ref --format='%(refname:short)' refs/heads/ | while read branch; do
    if [[ "$branch" != "$default_branch" ]]; then
      git branch -D "$branch" 2>/dev/null
    fi
  done

  git worktree add "$default_branch" "$default_branch"
  echo "\nReady! cd into '$default_branch/' to start working."
}

# Create a new feature branch worktree based on latest origin/main
# Usage: gwt-branch <branch-name> [base-branch]
gwtb() {
  local branch_name="$1"
  local base_branch="${2:-origin/main}"

  if [[ -z "$branch_name" ]]; then
    echo "Usage: gwt-branch <branch-name> [base-branch]"
    echo "  base-branch defaults to origin/main"
    return 1
  fi

  if [[ ! -f .git ]] || ! grep -q "gitdir:.*\.bare" .git 2>/dev/null; then
    echo "Error: not in a bare worktree root (no .git pointing to .bare)"
    return 1
  fi

  git fetch origin
  git worktree add "$branch_name" -b "$branch_name" "$base_branch"

  cd "$branch_name"
}

# Remove a worktree and optionally delete its branch
# Usage: gwtd <worktree-name> [-b to also delete the branch]
gwtd() {
  local worktree_name="$1"
  local delete_branch="$2"

  if [[ -z "$worktree_name" ]]; then
    echo "Usage: gwtd <worktree-name> [-b to also delete branch]"
    return 1
  fi

  # Find the bare repo root
  local bare_root
  bare_root=$(git worktree list --porcelain | head -1 | sed 's/worktree //')
  if [[ -z "$bare_root" ]]; then
    echo "Error: could not find bare repo root"
    return 1
  fi

  local worktree_path="$bare_root/$worktree_name"

  # If we're inside the worktree, cd back to the bare root first
  if [[ "$(pwd)" == "$worktree_path"* ]]; then
    cd "$bare_root"
  fi

  git worktree remove "$worktree_name"

  if [[ "$delete_branch" == "-b" ]]; then
    git branch -D "$worktree_name"
    echo "Removed worktree and deleted branch '$worktree_name'."
  else
    echo "Removed worktree '$worktree_name'. Branch still exists (use -b to delete it)."
  fi
}
