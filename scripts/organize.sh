#!/bin/bash
# Organize root directory

# Session notes and summaries
mv SESSION_*.md docs/session_notes/ 2>/dev/null
mv *_SESSION*.md docs/session_notes/ 2>/dev/null
mv CFG_FIX_SESSION_COMPLETE.md docs/session_notes/ 2>/dev/null

# Design and implementation documentation
mv *_DESIGN.md docs/design/ 2>/dev/null
mv *_IMPLEMENTATION*.md docs/design/ 2>/dev/null
mv *_STRATEGY.md docs/design/ 2>/dev/null
mv *_EVOLUTION.md docs/design/ 2>/dev/null
mv *_ANALYSIS.md docs/design/ 2>/dev/null
mv GLOBALS_*.md docs/design/ 2>/dev/null
mv QBE_*.md docs/design/ 2>/dev/null
mv TYPE_SYSTEM_*.md docs/design/ 2>/dev/null
mv ControlFlowGraph.md docs/design/ 2>/dev/null
mv UserDefinedTypes.md docs/design/ 2>/dev/null
mv arraysinfasterbasic.md docs/design/ 2>/dev/null
mv numerics.md docs/design/ 2>/dev/null

# Test results and verification
mv TEST_*.md docs/testing/ 2>/dev/null
mv VERIFICATION_TEST.md docs/testing/ 2>/dev/null
mv *_TEST_*.md docs/testing/ 2>/dev/null
mv TEST_*.txt docs/testing/ 2>/dev/null

# Bug fixes and issues
mv *_FIX*.md docs/session_notes/ 2>/dev/null
mv *_BUG*.md docs/session_notes/ 2>/dev/null
mv MULTILINE_IF_CFG_ISSUE.md docs/session_notes/ 2>/dev/null
mv NESTED_WHILE_IF_*.md docs/session_notes/ 2>/dev/null

# Feature documentation
mv *_FEATURE.md docs/design/ 2>/dev/null
mv *_DOCUMENTATION.md docs/design/ 2>/dev/null
mv FOR_LOOP_*.md docs/session_notes/ 2>/dev/null
mv PRINT_USING_IMPLEMENTATION.md docs/design/ 2>/dev/null
mv CONSTANTS_IMPLEMENTATION.md docs/design/ 2>/dev/null
mv DATA_READ_RESTORE_IMPLEMENTATION_PLAN.md docs/design/ 2>/dev/null
mv IIF_IMPLEMENTATION.md docs/design/ 2>/dev/null
mv NOT_OPERATOR_IMPLEMENTATION.md docs/design/ 2>/dev/null
mv ON_STATEMENTS_DOCUMENTATION.md docs/design/ 2>/dev/null

# Status and checklist docs
mv *_STATUS*.md docs/testing/ 2>/dev/null
mv *_CHECKLIST.md docs/design/ 2>/dev/null
mv *_SUMMARY.md docs/testing/ 2>/dev/null
mv NEXT_STEPS.md docs/ 2>/dev/null
mv COMPILER_VERSIONS.md docs/ 2>/dev/null
mv DEBUGGING_GUIDE.md docs/ 2>/dev/null
mv REMAINING_DATA_FIX.md docs/session_notes/ 2>/dev/null
mv SEMANTIC_ANALYZER_REVIEW.md docs/design/ 2>/dev/null

# Commit messages
mv COMMIT_MESSAGE_*.txt docs/session_notes/ 2>/dev/null

# Test programs
mv test_*.bas test_programs/scratch/ 2>/dev/null
mv hello.bas test_programs/examples/ 2>/dev/null
mv simple_on_test.bas test_programs/scratch/ 2>/dev/null
mv debug_compare.bas test_programs/scratch/ 2>/dev/null

# Build artifacts and temporary files
mv *.o build_artifacts/ 2>/dev/null
mv *.qbe build_artifacts/ 2>/dev/null
mv *.s build_artifacts/ 2>/dev/null
mv a.out build_artifacts/ 2>/dev/null
mv test1 test2 build_artifacts/ 2>/dev/null
mv test_* build_artifacts/ 2>/dev/null
mv simple_on build_artifacts/ 2>/dev/null
mv string_test build_artifacts/ 2>/dev/null
mv hello build_artifacts/ 2>/dev/null
mv fbc build_artifacts/ 2>/dev/null
mv temp_test build_artifacts/ 2>/dev/null
mv temp.s build_artifacts/ 2>/dev/null

echo "Organization complete!"
