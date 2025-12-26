#!/bin/bash
set -e

# Parse command line arguments
RUN_ANALYZER=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --analyzer)
      RUN_ANALYZER=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--analyzer]"
      echo "  --analyzer    Also run Xcode Static Analyzer"
      exit 1
      ;;
  esac
done

echo "🔍 Checking for Swift 6 concurrency issues..."

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

# Check for NSMutableData usage
echo -e "\n${YELLOW}📝 Checking for NSMutableData...${NC}"
NSMUTABLEDATA_FOUND=$(ast-grep --lang swift -p 'NSMutableData()' BrewDeck/ 2>/dev/null || true)
if [ -n "$NSMUTABLEDATA_FOUND" ]; then
    echo "$NSMUTABLEDATA_FOUND"
    echo -e "${YELLOW}⚠️  NSMutableData found - ensure it's wrapped in thread-safe Sendable class${NC}"
    echo -e "${YELLOW}💡 This is OK if immediately wrapped (e.g., DataWrapper(data: outputData))${NC}"
else
    echo -e "${GREEN}✓ No NSMutableData usage${NC}"
fi

# Check for mutable captures in closures
echo -e "\n${YELLOW}🔒 Checking for mutable variable captures...${NC}"
if ast-grep --lang swift -p 'var $VAR = $_; $CLOSURE { $VAR = $_ }' BrewDeck/ 2>/dev/null; then
    echo -e "${RED}⚠️  Mutable variable captures found - use thread-safe wrapper${NC}"
    ISSUES_FOUND=1
else
    echo -e "${GREEN}✓ No mutable capture issues${NC}"
fi

# Check for DispatchQueue usage (old concurrency)
echo -e "\n${YELLOW}⚡ Checking for old-style GCD...${NC}"
if ast-grep --lang swift -p 'DispatchQueue.$_.async' BrewDeck/ 2>/dev/null || \
   ast-grep --lang swift -p 'DispatchQueue.$_.sync' BrewDeck/ 2>/dev/null; then
    echo -e "${YELLOW}⚠️  DispatchQueue found - consider using async/await${NC}"
    ISSUES_FOUND=1
else
    echo -e "${GREEN}✓ No DispatchQueue usage${NC}"
fi

# Check for try? usage
echo -e "\n${YELLOW}⚠️  Checking for try? usage...${NC}"
TRY_OPTIONAL_FOUND=$(ast-grep --lang swift -p 'try? $_' BrewDeck/ 2>/dev/null || true)
if [ -n "$TRY_OPTIONAL_FOUND" ]; then
    echo "$TRY_OPTIONAL_FOUND"
    echo -e "${YELLOW}⚠️  try? found - acceptable if using ?? with fallback values${NC}"
    echo -e "${YELLOW}💡 For better debugging, consider: do { try ... } catch { log(error) }${NC}"
else
    echo -e "${GREEN}✓ No try? usage${NC}"
fi

# Check for NSHomeDirectory
echo -e "\n${YELLOW}🏠 Checking for NSHomeDirectory...${NC}"
if ast-grep --lang swift -p 'NSHomeDirectory()' BrewDeck/ 2>/dev/null; then
    echo -e "${YELLOW}⚠️  NSHomeDirectory found - use URL.homeDirectory${NC}"
else
    echo -e "${GREEN}✓ No NSHomeDirectory usage${NC}"
fi

# Check for replacingOccurrences
echo -e "\n${YELLOW}📝 Checking for replacingOccurrences...${NC}"
if ast-grep --lang swift -p '$STR.replacingOccurrences(of: $A, with: $B)' BrewDeck/ 2>/dev/null; then
    echo -e "${YELLOW}⚠️  replacingOccurrences found - use .replacing(_:with:)${NC}"
else
    echo -e "${GREEN}✓ No replacingOccurrences usage${NC}"
fi

echo -e "\n${GREEN}✅ Concurrency pattern check complete!${NC}"

if [ $ISSUES_FOUND -eq 1 ]; then
    echo -e "${YELLOW}Note: Some patterns were found that may cause concurrency issues.${NC}"
    echo -e "${YELLOW}Review CONCURRENCY_PREVENTION.md for best practices.${NC}"
fi

# Run Static Analyzer if requested
if [ "$RUN_ANALYZER" = true ]; then
    echo -e "\n${BLUE}🔬 Running Xcode Static Analyzer...${NC}"
    echo -e "${YELLOW}This may take a few minutes...${NC}\n"
    
    # Run the analyzer and capture output
    ANALYZER_LOG="/tmp/brewdeck-analyzer-$$.txt"
    
    if xcodebuild analyze \
        -project BrewDeck.xcodeproj \
        -scheme BrewDeck \
        -configuration Debug \
        OTHER_SWIFT_FLAGS="-Xfrontend -strict-concurrency=complete -Xfrontend -warn-concurrency" \
        2>&1 | tee "$ANALYZER_LOG"; then
        
        # Check for warnings/errors in the output
        if grep -qE "warning:|error:" "$ANALYZER_LOG"; then
            echo -e "\n${YELLOW}⚠️  Static Analyzer found issues:${NC}"
            grep -E "warning:|error:" "$ANALYZER_LOG" | head -20
            echo -e "\n${YELLOW}Full log saved to: $ANALYZER_LOG${NC}"
        else
            echo -e "\n${GREEN}✅ Static Analyzer passed with no issues!${NC}"
            rm -f "$ANALYZER_LOG"
        fi
    else
        echo -e "\n${RED}❌ Static Analyzer failed to run${NC}"
        echo -e "${YELLOW}Full log saved to: $ANALYZER_LOG${NC}"
    fi
fi

exit 0
