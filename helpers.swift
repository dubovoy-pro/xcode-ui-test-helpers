import XCTest


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
