workflow "New workflow" {
  resolves = ["jclem/action-mix"]
  on = "push"
}

action "jclem/action-mix" {
  uses = "jclem/actions/mix@master"
  args = "deps.get"
}
