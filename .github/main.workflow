workflow "New workflow" {
  on = "push"
  resolves = ["jclem/action-mix@master"]
}

action "jclem/action-mix@master" {
  uses = "jclem/actions-mix"
  args = "deps.get"
}
