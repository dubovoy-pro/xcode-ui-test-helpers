import XCTest


// MARK: Helpers


/// Все вспомогательные методы исходят из условия, что на устойстве
/// или симуляторе установлена русская локаль.

/// Метод удаляет ранее установленное приложение.
///
/// Полезно, когда нужно сбросить выданные ранее системные разрешения
/// для приложения на устройстве/симуляторе с iOS меньше 15
/// (resetAuthorizationStatus работае на iOS 15 и выше).
///
///````
///if #available(iOS 15.0, *) {
///    XCUIApplication().resetAuthorizationStatus(for: .userTracking)
///} else {
///    throw XCTSkip("Required API is not available for this test.")
///}
///````
///
/// - Parameter bundleDisplayName: Имя приложения.
///
func deleteApp(bundleDisplayName: String) {
    
    /// останавливаем на случай, если приложение было запущено
    /// на момент удаления
    XCUIApplication().terminate()

    let icon = springBoardApp.icons[bundleDisplayName]
    if icon.exists {
        // лонг тап
        icon.press(forDuration: 1)

        let buttonRemoveApp = springBoardApp.buttons["Удалить приложение"]
        if buttonRemoveApp.waitForExistence(timeout: 5) {
            buttonRemoveApp.tap()
        } else {
            XCTFail("Button \"Удалить приложение\" not found")
        }

        let buttonDeleteApp = springBoardApp.alerts.buttons["Удалить приложение"]
        if buttonDeleteApp.waitForExistence(timeout: 5) {
            buttonDeleteApp.tap()
        }
        else {
            XCTFail("Button \"Удалить приложение\" (second) not found")
        }

        let buttonDelete = springBoardApp.alerts.buttons["Удалить"]
        if buttonDelete.waitForExistence(timeout: 5) {
            buttonDelete.tap()
        }
        else {
            XCTFail("Button \"Удалить\" not found")
        }
    }
}


/// Формирует предикат для ожидания элемента
///
/// - Parameter element: Компонент, появления которого ожидаем.
///
func makeExistsExpectation(_ element: XCUIElement) -> XCTNSPredicateExpectation {
    let existsPredicate = NSPredicate(format: "exists == true")
    let expectation = XCTNSPredicateExpectation(predicate: existsPredicate, object: element)
    return expectation
}


/// Ожидает появления системного алерта с указанным заголовком
///
/// Системные алерты, такие как алерты системных разрешений, отображаются
/// в другом процессе с другим системным именем, отличным от имени приложения.
///
/// - Parameter alertTitle: Заголовок алерта, по которому он будет распознан.
///
func makeAlertElements(alertTitle: String) -> [XCUIElement] {
    let springBoardApp = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    return [springBoardApp.alerts[alertTitle], app.alerts[alertTitle]]
}


/// Используется для выполнения касания в заданной точке экрана
///
/// Для того, чтобы касание было выполнено корректно, необходимо
/// нормализовать координаты, т.е. учесть плотность точек на дюйм.
/// Метод позволят работать в привычных экранных координатах.
///
/// - Parameter point: Точка касания в экранных координатах.
///
func tapCoordinate(at point: CGPoint) {
    let normalized = XCUIApplication().coordinate(withNormalizedOffset: .zero)
    let offset = CGVector(dx: point.x, dy: point.y)
    let coordinate = normalized.withOffset(offset)
    coordinate.tap()
}


/// Используется для выполнения касания в первой точке экрана,
/// цвет которой соответствует заданному.
///
/// Цвет задается в RGB-формате. Альфа-канал не используется,
/// т.к. анализ цвета выполняется на основе скриншота, где альфа-канал
/// не предусмотрен.
///
/// - Parameters:
///   - red: красная часть RGB-цвета
///   - green: зеленая часть RGB-цвета
///   - blue: синяя часть RGB-цвета
///
func tapOnPixelWithRgbColor(red: Int, green: Int, blue: Int) {
    
    let image = XCUIApplication().screenshot().image

    guard let imageData = image.cgImage?.dataProvider?.data else {
        fatalError("Screenshot failed")
    }
    let data = CFDataGetBytePtr(imageData)!

    let width: Int = image.cgImage!.width
    let height: Int = image.cgImage!.height

    outerLoop: for x in 1...width {
        for y in 1...height {

            let pixelInfo = (width  * (y-1) + (x-1) ) * 4
            let red = Int(data[pixelInfo])
            let green = Int(data[(pixelInfo + 1)])
            let blue = Int(data[pixelInfo + 2])
            // альфа-канал не требуется
            // let alpha = Int(data[pixelInfo + 3])
            
            let borderOffset = 30 // исключаем края экрана - там касания нестабильные
            if x > borderOffset, x < width - borderOffset, y > borderOffset, y < height - borderOffset {
                if red == 39, green == 224, blue == 184 {
                    let scaleFactor: Int
                    if width == 1125 {
                        scaleFactor = 3 // для iPhone 13 mini
                    } else if width == 1170 {
                        scaleFactor = 3 // для iPhone 12
                    } else {
                        scaleFactor = 2 // при необходимост добавить прочие устройства
                    }
                    tapCoordinate(at: CGPoint(x: x / scaleFactor, y: y / scaleFactor))
                    break outerLoop
                }
            }
        }
    }

}


/// Ожидает появления одного из элементов, перечисленных в списке
///
/// В отличие от XCTWaiter.wait, который обрабатывает появление
/// всех элементов, метод работает в режиме oneOf.
/// Режим применяется для:
/// * обработки логических развилок в сценарии;
/// *  при последовательной обработке группы элементов,
/// порядок появления которых не определен. Например, при обработке алертов системных разрешений
/// ожидаем появления одного из алертов, потом убираем его
/// из списка, ожидаем следующего и т.д.
///
/// - Parameters:
///   - elements: набор элементов, один их которых следует найти
///   - timeout: ограничивающий временной интервал, в течение которого выполняется поиск
/// - Returns:
///  первый найденный XCUIElement из списка elements либо nil
func oneOfWaiter(elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {

    let step: TimeInterval = 0.1
    var counter: TimeInterval = 0
    let limit = timeout / step
    while counter < limit {
        for element in elements {
            if element.exists {
                return element
            }
        }
        counter = counter + 1
        Thread.sleep(forTimeInterval: step)
    }
    return nil
}


// MARK: Examples

/// Пример демонстрирует работу хелпера oneOfWaiter
///
func alertsOneOfExample() {
    
    let appName = "MY_COOL_APP"
    
    let app = XCUIApplication()
    
    // MARK: удаляем приложение с предыдущего теста (сбрасываем разрешения)

    deleteApp()
    
    // MARK: запускаем приложение

    app.launch()
    
    
    // MARK: обрабатываем алерт трекинга

    let trackingElements = makeAlertElements(alertTitle: "Разрешить приложению «\(appName)» отслеживать Ваши действия в приложениях и на веб-сайтах других компаний?")
    
    guard let alert = oneOfWaiter(elements: trackingElements, timeout: 3) else {
        XCTFail("Alert not found!")
        return
    }

    alert.buttons["Попросить не отслеживать"].tap()

    
    // MARK: Ожидаем появления формы входа, вводим номер телефона

    let phoneField = XCUIApplication().textFields["field_phone"]

    wait(for: [makeExistsExpectation(phoneField)], timeout: 5)
            
    phoneField.typeText("9")
    phoneField.typeText("5")
    phoneField.typeText("1")
    phoneField.typeText("0")
    phoneField.typeText("0")
    phoneField.typeText("5")
    phoneField.typeText("0")
    phoneField.typeText("4")
    phoneField.typeText("1")
    phoneField.typeText("2")

    let getSmsButton = XCUIApplication().buttons["button_enter"]
    getSmsButton.tap()

    
    // MARK: обрабатываем алерты геопозиции и пуш-уведомлений (порядок появления рандомный)

    let pushElementsSimulator = makeAlertElements(alertTitle: "“\(appName)” Would Like to Send You Notifications")
    let pushElementsDevice = makeAlertElements(alertTitle: "Приложение «\(appName)» запрашивает разрешение на отправку Вам уведомлений.")
    let geoElements = makeAlertElements(alertTitle: "Разрешить приложению «\(appName)» использовать Вашу геопозицию?")

    let allElements =
    geoElements +
    pushElementsSimulator +
    pushElementsDevice
    
    for _ in 1...2 { // 2 алерта, потому 2 итерации цикла
        guard let alert = oneOfWaiter(elements: allElements, timeout: 3) else {
            XCTFail("Alert not found!")
            return
        }
        
        if geoElements.contains(alert) {
            alert.buttons["При использовании"].tap()
            continue
        }
        if pushElementsSimulator.contains(alert) {
            alert.buttons["Allow"].tap()
            continue
        }
        if pushElementsDevice.contains(alert) {
            alert.buttons["Разрешить"].tap()
            continue
        }
    }
    
}
