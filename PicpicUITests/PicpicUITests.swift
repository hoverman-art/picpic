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

    private func launchApp(onboardingDone: Bool, resetBooks: Bool = false, pro: Bool = false,
                           freeReadingStub: Bool = false,
                           sudocStub: Bool = false,
                           demoBooks: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-onboarding.done", onboardingDone ? "YES" : "NO"]
        app.launchArguments += ["-stats.scanCount", "0"]
        if resetBooks {
            app.launchArguments += ["-uitest-reset-books"]
        }
        if pro {
            app.launchArguments += ["-uitest-pro"]
        }
        if freeReadingStub {
            app.launchArguments += ["-uitest-freereading-stub"]
        }
        if sudocStub {
            app.launchArguments += ["-uitest-sudoc-stub"]
        }
        if demoBooks {
            app.launchArguments += ["-uitest-demo-books"]
        }
        app.launch()
        return app
    }

    /// Fait défiler jusqu'à ce que l'élément soit réellement tapable.
    ///
    /// `exists` ne suffit pas : une vue hors de l'écran existe dans l'arbre
    /// d'accessibilité, et la taper ne déclenche rien. Depuis que l'étagère est
    /// remontée sous la recherche, le bandeau objectif passe sous la ligne de
    /// flottaison sur les petits écrans.
    private func scrollToTap(_ element: XCUIElement, in app: XCUIApplication,
                             swipes: Int = 4, file: StaticString = #filePath, line: UInt = #line) {
        var remaining = swipes
        while !element.isHittable && remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
        XCTAssertTrue(element.isHittable, "Élément inaccessible après défilement", file: file, line: line)
        element.tap()
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

        // Grille des features : uniquement des features livrées, aucun « Bientôt »
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Aller plus loin"].waitForExistence(timeout: 3), "Section grille premium absente")
        XCTAssertTrue(app.staticTexts["Dispo autour de moi"].exists, "Tuile disponibilité absente")
        XCTAssertTrue(app.staticTexts["Lire & écouter gratuit"].exists, "Tuile lecture gratuite absente")
        XCTAssertFalse(app.staticTexts["Bientôt"].exists, "Aucune tuile ne doit afficher « Bientôt »")
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
        // Le focus clavier peut rater au premier tap sur simulateur : on insiste.
        var attempts = 0
        repeat {
            searchField.tap()
            attempts += 1
        } while !app.keyboards.firstMatch.waitForExistence(timeout: 2) && attempts < 3
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
        // Guideline 3.1.2 : conditions de renouvellement + liens EULA/confidentialité.
        XCTAssertTrue(app.otherElements["paywall.legal"].exists, "Pied légal absent du paywall")

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

    // MARK: - Feature 10 : Lire & écouter gratuit (hors ligne via stub)

    @MainActor
    func testFreeLibraryOpensWithClassics() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true, freeReadingStub: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        app.swipeUp()
        let tile = app.buttons.containing(.staticText, identifier: "Lire & écouter gratuit").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 3), "Tuile lecture gratuite absente")
        tile.tap()

        XCTAssertTrue(app.navigationBars["Lire & écouter gratuit"].waitForExistence(timeout: 4),
                      "L'écran lecture gratuite doit s'ouvrir")
        XCTAssertTrue(app.staticTexts["Classiques à découvrir"].waitForExistence(timeout: 4),
                      "La section découverte doit s'afficher")
        XCTAssertTrue(app.staticTexts["Les Fleurs du mal"].waitForExistence(timeout: 4),
                      "Les classiques (stub) doivent se charger")
        app.buttons["Fermer"].tap()
        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 3))
    }

    // MARK: - Feature 11 : Rétrospective verrouillée pour un compte gratuit

    @MainActor
    func testStatsLockedShowsPaywall() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        let statsTile = app.buttons.containing(.staticText, identifier: "Ta rétrospective").firstMatch
        XCTAssertTrue(statsTile.waitForExistence(timeout: 3), "Tuile rétrospective absente")
        statsTile.tap()

        XCTAssertTrue(app.staticTexts["Picpic Pro"].waitForExistence(timeout: 4),
                      "La rétrospective verrouillée doit ouvrir le paywall")
    }

    // MARK: - Feature 12 : Rétrospective accessible en Pro

    @MainActor
    func testProUserOpensStats() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true, pro: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        let statsTile = app.buttons.containing(.staticText, identifier: "Ta rétrospective").firstMatch
        XCTAssertTrue(statsTile.waitForExistence(timeout: 3), "Tuile rétrospective absente")
        statsTile.tap()

        XCTAssertTrue(app.navigationBars["Ta rétrospective"].waitForExistence(timeout: 4),
                      "La rétrospective doit s'ouvrir pour un compte Pro")
        XCTAssertTrue(app.staticTexts["Scanne tes premiers livres"].waitForExistence(timeout: 3),
                      "L'état vide de la rétrospective doit s'afficher sans livres")
        app.buttons["Fermer"].tap()
        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 3))
    }

    // MARK: - Feature 13 : Sudoc — la recherche par sujet dans le fonds d'une BU

    @MainActor
    func testSudocSearchFromCampusCard() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true, sudocStub: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        let card = app.buttons["home.campusCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 3), "La carte Sudoc doit être en tête d'accueil")
        card.tap()

        XCTAssertTrue(app.textFields["sudoc.searchField"].waitForExistence(timeout: 4),
                      "L'écran Sudoc doit s'ouvrir")
        XCTAssertTrue(app.buttons["sudoc.scope"].firstMatch.exists || app.segmentedControls.firstMatch.exists,
                      "Le sélecteur BU/France doit être présent")

        // Une puce de sujet lance la recherche.
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sudoc.chip.'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 3), "Les sujets proposés doivent s'afficher")
        chip.tap()

        XCTAssertTrue(app.staticTexts["Les data contre la liberté"].waitForExistence(timeout: 6),
                      "Les notices doivent s'afficher")
        XCTAssertTrue(app.staticTexts["sudoc.summary"].exists || app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'notices'")).firstMatch.exists,
                      "Le total de notices doit être annoncé")
    }

    @MainActor
    func testSudocRecordDetailShowsSubjects() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true, sudocStub: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        app.buttons["home.campusCard"].tap()
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sudoc.chip.'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 4))
        chip.tap()

        let row = app.buttons["sudoc.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6), "Une ligne de résultat doit être touchable")
        row.tap()
        XCTAssertTrue(app.staticTexts["Sujets"].waitForExistence(timeout: 4),
                      "Le détail d'une notice doit lister ses sujets")
        XCTAssertTrue(app.staticTexts["Où l'emprunter"].exists,
                      "Le détail doit annoncer les exemplaires")
    }

    // MARK: - Feature 13 bis : la barre de recherche se valide et s'efface

    /// Le champ filtrait à la frappe mais n'offrait aucun moyen de valider ni
    /// de fermer le clavier : il passait pour cassé.
    @MainActor
    func testSearchCanBeSubmittedAndCleared() throws {
        let app = launchApp(onboardingDone: true, demoBooks: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        let field = app.textFields["home.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "La barre de recherche doit être sur l'accueil")
        field.tap()
        XCTAssertTrue(app.buttons["home.searchDone"].waitForExistence(timeout: 2),
                      "Champ vide et actif : un bouton doit permettre de refermer le clavier")

        field.typeText("mer")
        let clear = app.buttons["home.searchClear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 2), "Une croix doit permettre d'effacer la recherche")
        clear.tap()

        XCTAssertFalse(clear.exists, "La croix disparaît quand le champ est vide")
        XCTAssertTrue(app.staticTexts["Mes scans"].waitForExistence(timeout: 3),
                      "La bibliothèque complète revient après effacement")
    }

    // MARK: - Feature 14 : Objectifs & série de lecture

    @MainActor
    func testGoalsOpenFromStrip() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        let strip = app.buttons["home.goalStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 3), "Le bandeau objectif doit être sur l'accueil")
        scrollToTap(strip, in: app)

        XCTAssertTrue(app.navigationBars["Mon année"].waitForExistence(timeout: 4),
                      "L'écran objectifs doit s'ouvrir")
        XCTAssertTrue(app.otherElements["goals.streak"].waitForExistence(timeout: 3),
                      "La série doit être affichée")
        XCTAssertTrue(app.staticTexts["Terminés cette année"].exists)
    }

    // MARK: - Feature 15 : Citations

    @MainActor
    func testWriteAndKeepAQuote() throws {
        let app = launchApp(onboardingDone: true, resetBooks: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        app.swipeUp()
        let tile = app.buttons.containing(.staticText, identifier: "Citations").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 3), "La tuile Citations doit exister")
        tile.tap()

        XCTAssertTrue(app.navigationBars["Mes citations"].waitForExistence(timeout: 4))
        app.buttons["quotes.add"].tap()

        let manual = app.buttons["quote.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 4), "L'écriture à la main doit être proposée")
        manual.tap()

        let editor = app.textViews["quote.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        editor.tap()
        editor.typeText("La vie est ce qui arrive pendant que tu fais des projets.")

        app.buttons["quote.save"].tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'La vie est ce qui arrive'")).firstMatch
            .waitForExistence(timeout: 4),
                      "La citation gardée doit apparaître dans le carnet")
    }

    // MARK: - Feature 16 : Notes, étoiles et fiche de révision

    @MainActor
    func testNotesRatingAndRevisionSheet() throws {
        let app = launchApp(onboardingDone: true, demoBooks: true)

        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 5))
        app.staticTexts["L'Étranger"].firstMatch.tap()

        // Une étoile : la note doit être modifiable, ce que la fiche App Store promet.
        let fourth = app.buttons["book.star.4"]
        XCTAssertTrue(fourth.waitForExistence(timeout: 4), "Les étoiles doivent être touchables")
        fourth.tap()

        let notes = app.textViews["book.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3), "Les notes doivent être éditables")
        notes.tap()
        notes.typeText("L'absurde ne mène pas au désespoir")

        let revision = app.buttons["book.revision"]
        XCTAssertTrue(revision.waitForExistence(timeout: 3))
        revision.tap()

        XCTAssertTrue(app.navigationBars["Fiche de révision"].waitForExistence(timeout: 4),
                      "La fiche de révision doit s'ouvrir")
        XCTAssertTrue(app.staticTexts["Tes notes"].waitForExistence(timeout: 3),
                      "La fiche reprend les notes de l'utilisateur")
        // Le mode révision masque le texte jusqu'au rappel.
        app.buttons["revision.toggleTest"].tap()
        XCTAssertFalse(app.staticTexts["L'absurde ne mène pas au désespoir"].exists,
                       "En mode test, la note doit être masquée")
    }
}
