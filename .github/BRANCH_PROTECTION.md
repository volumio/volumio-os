# GitHub Branch Protection Configuration

This document describes how to configure branch protection for the volumio-os repository.

## Master Branch Protection

Navigate to: Settings -> Branches -> Add branch protection rule

### Branch name pattern
```
master
```

### Protection Settings

#### Protect matching branches

- [x] Require a pull request before merging
  - [x] Require approvals: 1 (adjust as needed)
  - [ ] Dismiss stale pull request approvals when new commits are pushed
  - [ ] Require review from Code Owners
  - [ ] Restrict who can dismiss pull request reviews
  - [x] Require approval of the most recent reviewable push

- [x] Require status checks to pass before merging
  - [x] Require branches to be up to date before merging
  - Status checks that are required:
    - `Validate PR Target`
    - `Validate Commit Messages`
    - `check` (shellcheck/shfmt)

- [ ] Require conversation resolution before merging

- [x] Require signed commits (optional but recommended)

- [ ] Require linear history

- [x] Do not allow bypassing the above settings
  - IMPORTANT: Leave this UNCHECKED initially for maintainer emergency access
  - Or check it but ensure "Allow specified actors to bypass" includes maintainers

#### Restrict who can push to matching branches

- [x] Restrict who can push to matching branches
  - Add maintainers who can push to master
  - This prevents direct pushes except from listed users

#### Rules applied to everyone including administrators

- [ ] Allow force pushes
  - Keep unchecked for master

- [ ] Allow deletions
  - Keep unchecked for master

### CRITICAL: Maintainer Override Access

To ensure you are never locked out:

1. Under "Restrict who can push to matching branches":
   - Add your GitHub username
   - Add any other trusted maintainers

2. Under "Allow specified actors to bypass required pull requests":
   - Add your GitHub username
   - This allows emergency direct pushes if needed

3. Alternatively, keep "Do not allow bypassing the above settings" UNCHECKED
   - This allows repository admins to bypass all rules in emergencies

## Feature Branch Protection (Optional)

For branches like `common`, `pi`, `amd64`, you may want lighter protection:

### Branch name pattern
```
common
```
(Repeat for other branches)

### Suggested Settings

- [x] Require a pull request before merging
  - [x] Require approvals: 1
- [x] Require status checks to pass before merging
  - Status checks: `check` (shellcheck)
- [ ] Restrict who can push (allow direct commits)

## Verification

After configuration, verify:

1. Try creating a PR from a fork to master - should fail validation
2. Try creating a PR from a fork to common - should pass
3. Try creating a PR from local branch to master - should pass
4. Check that maintainers can still push directly in emergencies

## Emergency Recovery

If locked out of master:

1. Go to Settings -> Branches -> master protection rule
2. Temporarily disable "Do not allow bypassing the above settings"
3. Push your emergency fix
4. Re-enable the setting

Or use GitHub CLI:
```bash
# Disable branch protection temporarily
gh api -X DELETE /repos/volumio/volumio-os/branches/master/protection

# Make your fix, then re-enable via UI
```

## API Alternative

Branch protection can also be configured via GitHub API:

```bash
curl -X PUT \
  -H "Authorization: token YOUR_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/volumio/volumio-os/branches/master/protection \
  -d '{
    "required_status_checks": {
      "strict": true,
      "contexts": ["Validate PR Target", "Validate Commit Messages", "check"]
    },
    "enforce_admins": false,
    "required_pull_request_reviews": {
      "required_approving_review_count": 1
    },
    "restrictions": {
      "users": ["YOUR_USERNAME"],
      "teams": []
    }
  }'
```

Note: Set `enforce_admins: false` to allow admin bypass for emergencies.
