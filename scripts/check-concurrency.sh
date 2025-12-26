#!/bin/bash
set -e

echo "🔍 Checking for Swift 6 concurrency issues..."

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

# Check for NSMutableData usage
echo -e "\n${YELLOW}📝 Checking for NSMutableData...${NC}"
if ast-grep --lang swift -p 'NSMutableData()' BrewDeck/ 2>/dev/null; then
    echo -e "${RED}⚠️  NSMutableData found - wrap in thread-safe Sendable class${NC}"
    ISSUES_FOUND=1
else
    echo -e "${GREEN}✓ No NSMutableData issues${NC}"
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
if ast-grep --lang swift -p 'try? $_' BrewDeck/ 2>/dev/null; then
    echo -e "${YELLOW}⚠️  try? found - consider proper error handling${NC}"
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

exit 0
