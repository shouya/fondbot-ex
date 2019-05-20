workflow "New workflow" {
  on = "push"
  resolves = ["jclem/action-mix@master"]
}

action "jclem/action-mix@master" {
  uses = "jclem/action-mix@master"
  args = "deps.get"
}
