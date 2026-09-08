//
//  MarketingShots.swift
//  PicpicUITests
//
//  Captures pour la fiche App Store. Ce n'est pas un test de non-régression :
//  il pilote l'app comme un utilisateur et joint chaque écran au rapport, d'où
//  `marketing/frame_shots.py` les reprend. Volontairement dans la cible de test
//  pour n'ajouter aucun code de capture à l'app livrée.
//
//  Extraction : xcrun xcresulttool export attachments --path <xcresult> …
//

import XCTest

final class MarketingShots: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Ces cas produisent des visuels, ils ne valident rien — et ils
        // dépendent du Sudoc et de Gutenberg. Hors campagne de captures, ils
        // n'ont rien à faire dans une suite de non-régression.
        //
        // Le préfixe TEST_RUNNER_ est obligatoire : xcodebuild ne transmet pas
        // l'environnement du shell au processus de test, il ne relaie que les
        // variables ainsi préfixées. Sans lui les cas sont ignorés et la
        // commande se termine au vert sans avoir produit une seule capture.
        //   TEST_RUNNER_PICPIC_CAPTURE=1 xcodebuild test \
        //     -only-testing:PicpicUITests/MarketingShots
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PICPIC_CAPTURE"] == "1",
                          "Captures marketing : régler TEST_RUNNER_PICPIC_CAPTURE=1 pour les produire.")
    }

    /// Laisse les vignettes de couverture arriver avant de déclencher la capture.
    ///
    /// Les jaquettes sont des `AsyncImage` qui partent sur covers.openlibrary.org,
    /// lequel répond en 2 à 11 s. La branche `default:` de `BookCard` confond
    /// « en cours » et « échec » et affiche le même aplat lavande, donc une
    /// capture prise trop tôt montre six rectangles violets au lieu des livres —
    /// et rien ne la distingue d'un échec réseau. Attendre l'apparition d'un
    /// libellé ne suffit pas : le texte est rendu avant que l'image ne parte.
    ///
    /// Faute d'identifiant sur l'état chargé, on temporise. C'est grossier, mais
    /// ça reste confiné à la cible de test : l'alternative propre — exposer
    /// l'état `.success` de l'AsyncImage — ajouterait du code de capture à
    /// l'app livrée, ce que ce fichier existe précisément pour éviter.
    private func letCoversLoad(_ seconds: TimeInterval = 14) {
        _ = XCTWaiter.wait(for: [expectation(description: "chargement des couvertures")],
                           timeout: seconds)
    }

    private func app(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // Profil étudiant en Lettres : c'est ce que la fiche met en avant, et
        // ça rend les propositions de sujets parlantes.
        app.launchArguments += ["-onboarding.done", "YES", "-uitest-demo-books",
                                "-reader.profile", "student",
                                "-reader.studyField", "lettres",
                                "-AppleLocale", "fr_FR"]
        app.launchArguments += extra
        app.launch()
        return app
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Sans bouchon réseau : une capture qui annoncerait « 3 notices » vendrait
    /// mal un catalogue de 15 millions de références.
    @MainActor
    func testCaptureHomeAndSudoc() throws {
        let app = app([])
        XCTAssertTrue(app.staticTexts["Ta bibliothèque"].waitForExistence(timeout: 8))
        letCoversLoad()
        shoot(app, "home_full")

        app.buttons["home.campusCard"].tap()
        let chip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'sudoc.chip.'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        // Attendre une vraie ligne de résultat : « notices » apparaît déjà dans
        // le texte d'introduction, et l'attendre shootait l'écran de chargement.
        XCTAssertTrue(app.buttons["sudoc.row"].firstMatch.waitForExistence(timeout: 30),
                      "Le Sudoc doit avoir répondu avant la capture")
        shoot(app, "sudoc_full")
    }

    @MainActor
    func testCaptureReader() throws {
        // Le chapitre 4 est du texte courant ; les premiers sont couverture et
        // préambule Gutenberg.
        let app = app(["-uitest-open", "reader", "-reader.progress.uitest-reader", "3"])
        XCTAssertTrue(app.buttons["reader.listen"].waitForExistence(timeout: 40),
                      "Le livre doit être téléchargé et affiché")
        shoot(app, "reader_full")
    }

    @MainActor
    func testCaptureProScreens() throws {
        let shelf = app(["-uitest-pro", "-uitest-open", "shelfscan"])
        XCTAssertTrue(shelf.navigationBars.firstMatch.waitForExistence(timeout: 8))
        shoot(shelf, "shelfscan_full")
        shelf.terminate()

        let stats = app(["-uitest-pro", "-uitest-open", "stats"])
        XCTAssertTrue(stats.navigationBars.firstMatch.waitForExistence(timeout: 8))
        shoot(stats, "stats_full")
        stats.terminate()

        let paywall = app(["-uitest-open", "paywall"])
        XCTAssertTrue(paywall.staticTexts["Picpic Pro"].waitForExistence(timeout: 8))
        shoot(paywall, "paywall_full")
    }

    @MainActor
    func testCaptureFreeReading() throws {
        let app = app(["-uitest-freereading-stub", "-uitest-open", "freereading"])
        XCTAssertTrue(app.staticTexts["Classiques à découvrir"].waitForExistence(timeout: 10))
        shoot(app, "freereading_full")
    }
}
