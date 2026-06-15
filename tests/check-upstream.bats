# tests/check-upstream.bats
setup() { source "${BATS_TEST_DIRNAME}/../scripts/check-upstream.sh"; }

@test "needs_build true when tags differ" {
  run needs_build "v1.0.31" "v1.0.30"; [ "$status" -eq 0 ]
}
@test "needs_build false when tags equal" {
  run needs_build "v1.0.30" "v1.0.30"; [ "$status" -eq 1 ]
}
@test "needs_build false when latest empty" {
  run needs_build "" "v1.0.30"; [ "$status" -eq 1 ]
}
@test "needs_build false when latest is literal null" {
  run needs_build "null" "v1.0.30"; [ "$status" -eq 1 ]
}
