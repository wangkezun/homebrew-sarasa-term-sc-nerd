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
@test "valid_tag accepts a normal version tag" {
  run valid_tag "v1.0.39"; [ "$status" -eq 0 ]
}
@test "valid_tag rejects newline injection" {
  run valid_tag $'v1.0\nmalicious=1'; [ "$status" -ne 0 ]
}
@test "valid_tag rejects spaces and shell metachars" {
  run valid_tag 'v1 $(rm -rf /)'; [ "$status" -ne 0 ]
}
