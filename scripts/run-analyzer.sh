#!/bin/bash
set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔬 Running Xcode Static Analyzer...${NC}\n"

# Configuration
SCHEME="BrewDeck"
PROJECT="BrewDeck.xcodeproj"
CONFIGURATION="Debug"
LOG_FILE="/tmp/brewdeck-analyzer-$(date +%Y%m%d-%H%M%S).txt"

# Run the analyzer
echo -e "Project: ${PROJECT}"
echo -e "Scheme: ${SCHEME}"
echo -e "Configuration: ${CONFIGURATION}\n"
echo -e "${YELLOW}This may take a few minutes...${NC}\n"

# Execute analyzer with strict concurrency checking
xcodebuild analyze \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    OTHER_SWIFT_FLAGS="-Xfrontend -strict-concurrency=complete -Xfrontend -warn-concurrency -Xfrontend -enable-actor-data-race-checks" \
    CLANG_ANALYZER_OUTPUT=plist-html \
    CLANG_ANALYZER_OUTPUT_DIR=build/analyzer-results \
    2>&1 | tee "$LOG_FILE"

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Analyze results
WARNINGS=$(grep -c "warning:" "$LOG_FILE" 2>/dev/null || echo "0")
ERRORS=$(grep -c "error:" "$LOG_FILE" 2>/dev/null || echo "0")
ANALYZER_WARNINGS=$(grep -c "analyzer" "$LOG_FILE" 2>/dev/null || echo "0")

if [ "$ERRORS" -gt 0 ]; then
    echo -e "${RED}❌ Analysis failed with $ERRORS error(s)${NC}\n"
    grep -E "error:" "$LOG_FILE" | head -20
    echo -e "\n${YELLOW}Full log: $LOG_FILE${NC}"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found $WARNINGS warning(s)${NC}\n"
    grep -E "warning:" "$LOG_FILE" | head -20
    
    if [ "$WARNINGS" -gt 20 ]; then
        echo -e "${YELLOW}... and $(($WARNINGS - 20)) more warnings${NC}"
    fi
    
    echo -e "\n${YELLOW}Full log: $LOG_FILE${NC}"
    
    # Check for analyzer-specific output
    if [ -d "build/analyzer-results" ]; then
        HTML_COUNT=$(find build/analyzer-results -name "*.html" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$HTML_COUNT" -gt 0 ]; then
            echo -e "\n${BLUE}📊 HTML reports generated: build/analyzer-results/${NC}"
            echo -e "${BLUE}Open them with: open build/analyzer-results/*.html${NC}"
        fi
    fi
else
    echo -e "${GREEN}✅ Static Analyzer passed with no issues!${NC}\n"
    rm -f "$LOG_FILE"
    exit 0
fi

# Provide helpful information
echo -e "\n${BLUE}💡 Common issues to check:${NC}"
echo -e "  • Memory leaks and retain cycles"
echo -e "  • Null pointer dereferences"
echo -e "  • Uninitialized variables"
echo -e "  • Dead code and unreachable conditions"
echo -e "  • Concurrency and data race issues"
echo -e "  • API misuse"

exit 0
