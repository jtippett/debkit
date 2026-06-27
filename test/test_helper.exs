# The `:dpkg` suite shells out to `dpkg-deb` to prove real-world interop. It's
# present on Debian/Ubuntu (including the Linux CI runners) and via Homebrew on
# macOS; exclude it automatically when the binary isn't installed.
exclude = if System.find_executable("dpkg-deb"), do: [], else: [dpkg: true]

ExUnit.start(exclude: exclude)
