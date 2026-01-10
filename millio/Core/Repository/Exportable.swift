//
//  Exportable.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

protocol Exportable {
    func export() throws -> Data
}
