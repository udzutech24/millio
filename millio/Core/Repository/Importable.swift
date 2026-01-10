//
//  Importable.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

protocol Importable {
    static func `import`(_ data: Data) throws
}
