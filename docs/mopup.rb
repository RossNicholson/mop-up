# The cask for RossNicholson/homebrew-tap (Casks/mopup.rb). The first release
# copies it into the tap; every release then bumps version and sha256 there.
cask "mopup" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/RossNicholson/mop-up/releases/download/v#{version}/MopUp-#{version}.dmg"
  name "Mop Up"
  desc "Disk cleaner and app uninstaller"
  homepage "https://github.com/RossNicholson/mop-up"

  depends_on macos: :sonoma

  app "Mop Up.app"

  uninstall quit: "com.rossnicholson.MopUp"

  zap trash: [
    "~/Library/Application Support/Mop Up",
    "~/Library/Caches/com.rossnicholson.MopUp",
    "~/Library/Preferences/com.rossnicholson.MopUp.plist",
    "~/Library/Saved Application State/com.rossnicholson.MopUp.savedState",
  ]
end
