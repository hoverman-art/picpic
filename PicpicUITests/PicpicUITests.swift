//
//  PicpicUITests.swift
//  PicpicUITests
//
//  Feature-by-feature UI tests, driven via xcodebuild (test_sim).
//  UserDefaults are overridden through launch arguments so each
//  test starts from a known state.
//

import XCTest

final class PicpicUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(onboardingDone: Bool, resetBooks: Bool = false, pro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-onboarding.done", onboardingDone ? "YES" : "NO"]
        app.launchArguments += ["-stats.scanCount", "0"]
        if resetBooks {
            app.launchArguments += ["-uitest-reset-books"]
        }
        if pro {
            app.launchArguments += ["-uitest-pro"]
        }
        app.launch()
        return app
    }

    // MARK: - Feature 1 : Onboarding complet

    @MainActor
    func testOnboardingFlowToHome() throws {
        let app = launchApp(onboardingDone: false)

        // Page 1 : accueil
        let continueButton = app.buttons["Continuer"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Bouton Continuer absent (page 1)")
        continueButton.tap()

        // Page 2 : features
        XCTAssertTrue(app.staticTexts["Dispo en bibliothèque"].waitForExistence(timeout: 3))
        continueButton.tap()

        // Page 3 : profil — Continuer désactivé tant qu'aucun profil choisi
        let studentCard = app.buttons.containing(.staticText, identifier: "Étudiant·e").firstMatch
        XCTAssertTrue(studentCard.waitForExistence(timeout: 3), "Carte profil Étudiant absente")
        studentCard.tap()
        // La filière apparaît pour les étudiants
        XCTAssertTrue(app.staticTexts["Ta filière"].waitForExistence(timeout: 3), "Choix de filière absent")
        app.buttons["Droit"].firstMatch.tap()
        continueButton.tap()

        // Page 4 : prêt à scanner
        let startButton = app.buttons["C'est parti"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3), "Bouton final absent (page 4)")
        startButton.tap()

        // Home
        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5), "Home absente après onboarding")
    }

    // MARK: - Feature 2 : Skip de l'onboarding

    @MainActor
    func testOnboardingSkip() throws {
        let app = launchApp(onboardingDone: false)
        let skip = app.buttons["Passer"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5), "Skip ne mène pas à la home")
    }

    // MARK: - Feature 3 : Home — état vide + grille premium

    @MainActor
    func testHomeEmptyStateAndFeatureGrid() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scanne ton premier livre"].exists, "État vide absent")

        // Grille des features premium (les 4 premières tuiles visibles sans scroll profond)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Aller plus loin"].waitForExistence(timeout: 3), "Section grille premium absente")
        XCTAssertTrue(app.staticTexts["Dispo autour de moi"].exists, "Tuile disponibilité absente")

        // Une tuile "Bientôt" affiche le modal coming soon
        app.swipeUp()
        let statsTile = app.buttons.containing(.staticText, identifier: "Stats & Rétrospective").firstMatch
        if statsTile.exists {
            statsTile.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3), "Alerte Bientôt absente")
            app.alerts.buttons["OK"].tap()
        }
    }

    // MARK: - Feature 4 : Scanner (sheet + saisie manuelle)

    @MainActor
    func testScannerSheetOpensWithManualEntry() throws {
        let app = launchApp(onboardingDone: true)

        let scanButton = app.buttons["Scanner"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
        scanButton.tap()

        // Sur simulateur : pas de caméra → fallback saisie manuelle
        XCTAssertTrue(app.navigationBars["Scanner un livre"].waitForExistence(timeout: 4), "Sheet scanner absente")
        XCTAssertTrue(app.textFields["isbnField"].waitForExistence(timeout: 3), "Champ ISBN manuel absent")

        app.buttons["Fermer"].tap()
        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 3))
    }

    // MARK: - Feature 5 : Scan manuel bout-en-bout (réseau requis)

    @MainActor
    func testManualScanAddsBookAndOpensDetail() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true)

        app.buttons["Scanner"].tap()
        let isbnField = app.textFields["isbnField"]
        XCTAssertTrue(isbnField.waitForExistence(timeout: 4))
        isbnField.tap()
        // L'Étranger — Albert Camus (Folio), très stable sur Google Books/Open Library.
        isbnField.typeText("9782070360024")
        app.buttons["Valider l'ISBN"].tap()

        // Retour home, le livre apparaît dans "Mes scans" (fetch réseau ≤ 15 s)
        XCTAssertTrue(app.staticTexts["Mes scans"].waitForExistence(timeout: 20), "Le livre scanné n'apparaît pas")
    }

    // MARK: - Feature 6 : Recherche

    @MainActor
    func testSearchFieldAcceptsInput() throws {
        let app = launchApp(onboardingDone: true)

        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("roman sur la mer")
        // Pas de crash + le champ contient bien la requête
        XCTAssertTrue((searchField.value as? String)?.contains("mer") == true)
    }

    // MARK: - Feature 7 : Paywall depuis la bannière Pro

    @MainActor
    func testPaywallOpensFromProBanner() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        app.swipeUp()
        let banner = app.buttons["home.proBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 3), "Bannière Picpic Pro absente pour un compte gratuit")
        banner.tap()

        // Le paywall affiche les trois formules, lifetime comprise
        XCTAssertTrue(app.staticTexts["Picpic Pro"].waitForExistence(timeout: 4), "Titre du paywall absent")
        XCTAssertTrue(app.buttons["paywall.plan.lifetime"].waitForExistence(timeout: 3), "Formule à vie absente")
        XCTAssertTrue(app.buttons["paywall.plan.annual"].exists, "Formule annuelle absente")
        XCTAssertTrue(app.buttons["paywall.plan.monthly"].exists, "Formule mensuelle absente")
        XCTAssertTrue(app.buttons["paywall.cta"].exists, "CTA d'achat absent")
        XCTAssertTrue(app.buttons["paywall.restore"].exists, "Bouton restaurer absent")

        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 3))
    }

    // MARK: - Feature 8 : Scan d'étagère verrouillé pour un compte gratuit

    @MainActor
    func testShelfScanLockedShowsPaywall() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        app.swipeUp()
        let shelfTile = app.buttons.containing(.staticText, identifier: "Scan d'étagère").firstMatch
        XCTAssertTrue(shelfTile.waitForExistence(timeout: 3), "Tuile scan d'étagère absente")
        shelfTile.tap()

        XCTAssertTrue(app.staticTexts["Picpic Pro"].waitForExistence(timeout: 4),
                      "La tuile verrouillée doit ouvrir le paywall")
    }

    // MARK: - Feature 9 : Scan d'étagère accessible en Pro

    @MainActor
    func testProUserOpensShelfScan() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true, pro: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.proBanner"].exists, "La bannière Pro ne doit pas s'afficher en Pro")

        app.swipeUp()
        let shelfTile = app.buttons.containing(.staticText, identifier: "Scan d'étagère").firstMatch
        XCTAssertTrue(shelfTile.waitForExistence(timeout: 3), "Tuile scan d'étagère absente")
        shelfTile.tap()

        XCTAssertTrue(app.navigationBars["Scan d'étagère"].waitForExistence(timeout: 4),
                      "La feature scan d'étagère doit s'ouvrir pour un compte Pro")
        XCTAssertTrue(app.buttons["shelfscan.pickPhoto"].waitForExistence(timeout: 3),
                      "Le choix de photo doit être proposé")
        app.buttons["Fermer"].tap()
        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 3))
    }
}
