//
//  TickerCode.swift
//  ARQExchange
//
//  Created by Pann Cherry on 6/5/26.
//
import Foundation

struct TickerCode: Identifiable, Equatable, Decodable {
    let id: String
    let code: String

    nonisolated init(id: String? = nil, code: String) {
        self.id = id ?? UUID().uuidString
        self.code = code
    }

    nonisolated init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let code = try container.decode(String.self, forKey: .code)
            let id = try container.decode(String.self, forKey: .id)
            self.init(id: id, code: code)
        } else {
            let container = try decoder.singleValueContainer()
            try self.init(code: container.decode(String.self))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case code
    }
}
