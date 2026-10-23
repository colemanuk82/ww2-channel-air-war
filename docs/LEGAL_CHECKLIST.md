# Release legal checklist

Not legal advice. Work through this before announcing a release more widely, and have a qualified person review the EULA and privacy text.

## Placeholders to fill (docs/legal and legal gate)
- [ ] `{PUBLISHER}` - the legal name that publishes the game (EULA, privacy policy, credits)
- [ ] `{CONTACT}` - a monitored contact address
- [ ] `{JURISDICTION}` - governing law and courts named in the EULA
- [ ] Re-read the EULA and privacy policy after any new feature that touches the network or stores data (the manual "Check for updates" button is already covered in PRIVACY.txt)

## Third-party material
- [ ] Music: Pixabay Content Licence - confirm each track is still listed on Pixabay under that licence and the credits in CREDITS.txt match the files in `assets/`
- [ ] Voices: ElevenLabs text-to-speech - check the plan in use allows commercial use and redistribution of generated audio; keep the invoice or plan record
- [ ] Menu paintings and any other AI-generated images: check the generator's terms for redistribution; the game states they are AI-generated
- [ ] `assets/ui/controller_outline.png` - confirm where it came from and its licence; add it to CREDITS.txt or replace it
- [ ] Map data: OpenStreetMap (ODbL), Sentinel-2 cloudless (CC BY 4.0), ESA WorldCover (CC BY 4.0), Terrain Tiles - attribution text is in CREDITS.txt and shown in-game
- [ ] Fonts: Barlow (SIL OFL 1.1) licence text shipped with the game
- [ ] Engine: Godot (MIT) and its bundled third-party licences shown in-game; FidelityFX FSR 2 (MIT)
- [ ] NVIDIA DLSS / Streamline / Reflex: not redistributed; downloaded by the player from NVIDIA's repository. Do not add the DLL files to the public zip or installer

## Trademarks and history
- [ ] Aircraft names are used descriptively; squadrons and units in the career mode are invented
- [ ] No real person's likeness or voice; fictional commentary is labelled as original
- [ ] The README disclosure ("Honest disclosure") still matches how the game was made

## Distribution
- [ ] Release assets contain only: the game exe, EULA, PRIVACY, CREDITS (zip) and the installer
- [ ] Donation link is optional and voluntary (PayPal.me); the game itself sends nothing
- [ ] Photosensitivity warning (EPILEPSY.txt) is shown once per launch
- [ ] README claims (system requirements, single-player only) verified on real hardware
