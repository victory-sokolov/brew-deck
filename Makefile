# Makefile for BrewDeck Swift Project
# Provides commands for linting, formatting, and code quality checks

.PHONY: help lint lint-fix format format-check concurrency-check analyze all check clean

# Linting targets
lint: ## Run SwiftLint to check for style violations
	@echo "🔍 Running SwiftLint..."
	swiftlint --strict

lint-fix: ## Run SwiftLint with auto-fix for style violations
	@echo "🔧 Running SwiftLint with auto-fix..."
	swiftlint --fix

# Formatting targets
format: ## Format Swift code using SwiftFormat
	@echo "📝 Formatting Swift code..."
	swiftformat --config .swiftformat .

format-check: ## Check Swift code formatting without modifying files
	@echo "🔍 Checking Swift code formatting..."
	swiftformat --dryrun --config .swiftformat .

# Code quality checks
concurrency-check: ## Check for Swift 6 concurrency issues
	@echo "🔒 Checking for Swift 6 concurrency issues..."
	./scripts/check-concurrency.sh

analyze: ## Run Xcode Static Analyzer with concurrency checks
	@echo "🔬 Running Xcode Static Analyzer..."
	./scripts/run-analyzer.sh

# Combined targets
all: format lint-fix ## Format code and auto-fix linting issues
	@echo "✅ Code formatted and linting issues auto-fixed"

check: format-check lint ## Check formatting and linting (no modifications)
	@echo "✅ Formatting and linting checks passed"

# Clean target
clean: ## Remove build artifacts
	@echo "🧹 Cleaning build artifacts..."
	rm -rf build/
	rm -rf BrewDeck.xcodeproj/xcuserdata/
	rm -rf BrewDeck.xcodeproj/project.xcworkspace/xcuserdata/


.DEFAULT_GOAL := help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sort \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
