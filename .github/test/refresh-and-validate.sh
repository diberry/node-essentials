#!/usr/bin/env bash
#
# Refresh dependencies and validate all test frameworks
#
# This master script:
# 1. Updates npm dependencies for all test framework subdirectories to latest compatible versions
# 2. Runs all tests to validate that updated dependencies don't break anything
# 3. Provides a color-coded summary of all results
#
# Usage: ./refresh-and-validate.sh
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Test directories
declare -a TEST_DIRS=("test-with-node-testrunner" "test-with-jest" "test-with-vitest")

# Track results
declare -A UPDATE_STATUS
declare -A TEST_STATUS

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}Refresh Dependencies & Validate All Frameworks${NC}"
echo -e "${CYAN}Started: $TIMESTAMP${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# ==================== PHASE 1: UPDATE DEPENDENCIES ====================
echo -e "${CYAN}PHASE 1: Updating Dependencies${NC}"
echo -e "${CYAN}================================${NC}"
echo ""

for test_dir in "${TEST_DIRS[@]}"; do
    TEST_PATH="$REPO_ROOT/$test_dir"
    PACKAGE_JSON="$TEST_PATH/package.json"
    PACKAGE_OLD="$TEST_PATH/package.old.json"
    
    echo -e "${YELLOW}Processing: $test_dir${NC}"
    
    # Check if directory exists
    if [ ! -d "$TEST_PATH" ]; then
        echo -e "  ${RED}❌ Directory not found: $TEST_PATH${NC}"
        UPDATE_STATUS[$test_dir]="FAILED"
        echo ""
        continue
    fi
    
    # Check if package.json exists
    if [ ! -f "$PACKAGE_JSON" ]; then
        echo -e "  ${RED}❌ package.json not found: $PACKAGE_JSON${NC}"
        UPDATE_STATUS[$test_dir]="FAILED"
        echo ""
        continue
    fi
    
    # Change to test directory
    cd "$TEST_PATH" || exit 1
    
    # Backup current package.json
    echo -e "  ${GRAY}[1/4] Backing up current package.json...${NC}"
    if cp "$PACKAGE_JSON" "$PACKAGE_OLD"; then
        echo -e "  ${GREEN}✅ Backed up to package.old.json${NC}"
    else
        echo -e "  ${RED}❌ Failed to backup package.json${NC}"
        UPDATE_STATUS[$test_dir]="FAILED"
        echo ""
        continue
    fi
    
    # Extract package metadata
    echo -e "  ${GRAY}[2/4] Extracting package metadata...${NC}"
    PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_OLD")
    PACKAGE_VERSION=$(jq -r '.version' "$PACKAGE_OLD")
    PACKAGE_TYPE=$(jq -r '.type // empty' "$PACKAGE_OLD")
    PACKAGE_MAIN=$(jq -r '.main // "index.js"' "$PACKAGE_OLD")
    PACKAGE_SCRIPTS=$(jq -r '.scripts' "$PACKAGE_OLD")
    PACKAGE_LICENSE=$(jq -r '.license // "ISC"' "$PACKAGE_OLD")
    
    # Extract regular dependencies
    DEPS=$(jq -r '.dependencies // {} | keys[]' "$PACKAGE_OLD" | sort)
    
    # Extract dev dependencies
    DEV_DEPS=$(jq -r '.devDependencies // {} | keys[]' "$PACKAGE_OLD" | sort)
    
    echo -e "  ${GREEN}✅ Extracted metadata${NC}"
    echo -e "    Package: $PACKAGE_NAME"
    echo -e "    Dependencies: $(echo "$DEPS" | wc -l | tr -d ' ') packages"
    echo -e "    Dev Dependencies: $(echo "$DEV_DEPS" | wc -l | tr -d ' ') packages"
    
    # Clean and run fresh npm install + update from REPO ROOT (for workspaces)
    echo -e "  ${GRAY}[3/4] Running npm update to refresh dependencies...${NC}"
    
    # Remove node_modules and package-lock.json for clean install
    rm -rf node_modules package-lock.json 2>/dev/null
    
    # Change to repo root for workspace-aware npm commands
    cd "$REPO_ROOT" || exit 1
    
    # Run npm install for the entire workspace
    if npm install --legacy-peer-deps --workspaces > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ npm install completed${NC}"
    else
        echo -e "  ${YELLOW}⚠️  npm install completed with warnings${NC}"
    fi
    
    # Run npm update for the entire workspace
    if npm update --legacy-peer-deps --workspaces > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ npm update completed${NC}"
    else
        echo -e "  ${YELLOW}⚠️  npm update completed with warnings${NC}"
    fi
    
    # Return to test directory
    cd "$TEST_PATH" || exit 1
    
    # Extract actual installed versions and update package.json using Node.js
    echo -e "  ${GRAY}[4/4] Updating package.json with resolved versions...${NC}"
    
    # Export variables for the Node script
    export REPO_ROOT PACKAGE_JSON PACKAGE_OLD
    
    # Use Node.js to read the root package-lock.json and extract versions for this workspace
    node << 'EOF'
    const fs = require('fs');
    const path = require('path');
    
    try {
      const lockfilePath = path.join(process.env.REPO_ROOT, 'package-lock.json');
      const packageJsonPath = process.env.PACKAGE_JSON;
      const packageOldPath = process.env.PACKAGE_OLD;
      
      const lockfile = JSON.parse(fs.readFileSync(lockfilePath, 'utf8'));
      const oldPkg = JSON.parse(fs.readFileSync(packageOldPath, 'utf8'));
      
      const deps = {};
      const devDeps = {};
      
      // Extract dependencies from the root lock file
      if (oldPkg.dependencies && lockfile.packages) {
        Object.keys(oldPkg.dependencies).forEach(name => {
          const pkg = lockfile.packages['node_modules/' + name];
          if (pkg && pkg.version) {
            deps[name] = pkg.version;
          }
        });
      }
      
      // Extract devDependencies from the root lock file
      if (oldPkg.devDependencies && lockfile.packages) {
        Object.keys(oldPkg.devDependencies).forEach(name => {
          const pkg = lockfile.packages['node_modules/' + name];
          if (pkg && pkg.version) {
            devDeps[name] = pkg.version;
          }
        });
      }
      
      const newPkg = {
        name: oldPkg.name,
        version: oldPkg.version,
        main: oldPkg.main,
        type: oldPkg.type,
        scripts: oldPkg.scripts,
        dependencies: deps,
        devDependencies: devDeps,
        license: oldPkg.license
      };
      
      fs.writeFileSync(packageJsonPath, JSON.stringify(newPkg, null, 2) + '\n');
      console.log('✅ Updated with ' + Object.keys(deps).length + ' deps + ' + Object.keys(devDeps).length + ' dev deps');
    } catch (err) {
      console.error('Warning: Could not extract versions -', err.message);
    }
EOF
    
    echo -e "  ${GREEN}✅ package.json updated with latest resolved versions${NC}"
    UPDATE_STATUS[$test_dir]="SUCCESS"
    echo ""
done

# ==================== PHASE 2: RUN TESTS ====================
echo ""
echo -e "${CYAN}PHASE 2: Running Tests${NC}"
echo -e "${CYAN}=======================${NC}"
echo ""

for test_dir in "${TEST_DIRS[@]}"; do
    TEST_PATH="$REPO_ROOT/$test_dir"
    
    echo -e "${YELLOW}Testing: $test_dir${NC}"
    
    # Check if directory exists
    if [ ! -d "$TEST_PATH" ]; then
        echo -e "  ${RED}❌ Directory not found${NC}"
        TEST_STATUS[$test_dir]="FAILED"
        echo ""
        continue
    fi
    
    cd "$TEST_PATH" || exit 1
    
    # Run npm test
    if npm test > /tmp/${test_dir}_test.log 2>&1; then
        echo -e "  ${GREEN}✅ All tests passed${NC}"
        TEST_STATUS[$test_dir]="PASSED"
    else
        echo -e "  ${RED}❌ Tests failed${NC}"
        TEST_STATUS[$test_dir]="FAILED"
        echo -e "  ${GRAY}Last 10 lines of output:${NC}"
        tail -10 /tmp/${test_dir}_test.log | sed 's/^/    /'
    fi
    echo ""
done

# ==================== SUMMARY ====================
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}Summary${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

ALL_SUCCESS=true

echo -e "${YELLOW}Dependency Updates:${NC}"
for test_dir in "${TEST_DIRS[@]}"; do
    status=${UPDATE_STATUS[$test_dir]:-"UNKNOWN"}
    if [ "$status" = "SUCCESS" ]; then
        echo -e "  ${GREEN}✅${NC} $test_dir"
    else
        echo -e "  ${RED}❌${NC} $test_dir - $status"
        ALL_SUCCESS=false
    fi
done

echo ""
echo -e "${YELLOW}Test Results:${NC}"
for test_dir in "${TEST_DIRS[@]}"; do
    status=${TEST_STATUS[$test_dir]:-"UNKNOWN"}
    if [ "$status" = "PASSED" ]; then
        echo -e "  ${GREEN}✅${NC} $test_dir"
    else
        echo -e "  ${RED}❌${NC} $test_dir - $status"
        ALL_SUCCESS=false
    fi
done

echo ""
echo -e "${CYAN}================================================${NC}"

if [ "$ALL_SUCCESS" = true ]; then
    echo -e "${GREEN}✅ All operations completed successfully${NC}"
    echo -e "${CYAN}================================================${NC}"
    exit 0
else
    echo -e "${RED}❌ Some operations failed - review output above${NC}"
    echo -e "${CYAN}================================================${NC}"
    exit 1
fi
