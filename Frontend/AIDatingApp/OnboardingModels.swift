//
//  OnboardingModels.swift
//  AIDatingApp
//
//  Created by Tab Chao on 8/13/25.
//

import Foundation

struct FormDef: Decodable {
  let version: Int
  let title: String
  let locales: [String]
  let steps: [StepDef]
}

struct StepDef: Decodable, Identifiable {
  let id: String
  let type: StepType
  let title: String?
  let description: String?
  let question: String?
  let options: [OptionDef]?
  let placeholder: String?
  let required: Bool?
  let validation: [String:Int]?
  let next: String?
  // 其他欄位（例如 upload 的 config）省略，先不影響渲染

  var displayTitle: String { question ?? title ?? "" }
}

struct OptionDef: Decodable, Identifiable {
  var id: String { value }
  let value: String
  let label: String
}

enum StepType: String, Decodable {
  case intro
  case choice
  case text
  case textarea
  case number
  case upload
  case finish
  case singleSelect = "single-select"
  case multiSelect  = "multi-select"
}
