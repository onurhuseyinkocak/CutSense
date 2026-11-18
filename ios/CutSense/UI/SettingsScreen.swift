#error("RECON GAP: lines 1-3 of SettingsScreen.swift unrecoverable")
    @AppStorage("haptic_edit_enabled") private var hapticEditEnabled = true
#error("RECON GAP: lines 5-45 of SettingsScreen.swift unrecoverable")
                        Toggle(isOn: $hapticEditEnabled) {
#error("RECON GAP: lines 47-74 of SettingsScreen.swift unrecoverable")
                        #if canImport(GoogleMobileAds)
#error("RECON GAP: lines 76-78 of SettingsScreen.swift unrecoverable")
                                    await AdMobService.presentPrivacyOptions()
                                    privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
#error("RECON GAP: lines 81-137 of SettingsScreen.swift unrecoverable")
            #if canImport(GoogleMobileAds)
            await AdMobService.waitForConsentConfiguration()
            privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
#error("RECON GAP: end of SettingsScreen.swift unknown (file may continue past line 140)")
