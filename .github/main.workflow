workflow "New workflow" {
  on = "push"
  resolves = ["Upload assets to Release"]
}

action "jclem/action-mix@master" {
  uses = "jclem/action-mix@master"
  runs = ".github/build.sh"
}

action "Upload assets to Release" {
  uses = "JasonEtco/upload-to-release@master"
  needs = ["jclem/action-mix@master"]
  secrets = ["GITHUB_TOKEN"]
  args = "_build/prod/rel/fondbot_ex/releases/0.1.0/fondbot_ex.tar.gz"
}
