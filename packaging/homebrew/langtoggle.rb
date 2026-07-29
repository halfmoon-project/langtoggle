# Homebrew cask. 이 리포가 아니라 별도 탭 리포의 Casks/ 로 간다:
#
#   halfmoon-project/homebrew-tap  ->  Casks/langtoggle.rb
#
# 그러면 사용자는 이렇게 깐다:
#
#   brew install --cask halfmoon-project/tap/langtoggle
#
# 공식 homebrew/cask 는 별·포크 수 기준(notability)이 있어서 아직 안 받아 준다. 자체 탭은 기준이 없다.
# version/sha256 은 릴리스마다 갈아 준다 — './make_app.sh dist' 가 마지막에 sha256 을 출력한다.
cask "langtoggle" do
  version "1.1.0"
  sha256 "TBD"

  url "https://github.com/halfmoon-project/langtoggle/releases/download/v#{version}/LangToggle-#{version}.zip"
  name "LangToggle"
  desc "Floating keycap that shows and switches the current input source"
  homepage "https://github.com/halfmoon-project/langtoggle"

  # 앱이 Sparkle 로 스스로 업데이트한다. 이 줄이 없으면 brew 가 자기 장부(1.1.0)를 믿고
  # 이미 1.2.0 이 된 앱을 도로 1.1.0 으로 덮어쓴다.
  auto_updates true

  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "LangToggle.app"

  zap trash: [
    "~/Library/Application Support/LangToggle",
    "~/Library/Preferences/com.sanghyeon.langtoggle.plist",
  ]
end
