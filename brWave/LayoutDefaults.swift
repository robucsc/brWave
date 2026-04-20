//
//  LayoutDefaults.swift
//  brWave
//
//  Source-committed layout defaults. Tune positions in the app, hit Export,
//  paste the generated code here, then commit. UserDefaults overrides layer on top.
//

import CoreGraphics

enum LayoutDefaults {
    static let offsets: [String: CGSize] = [
        "A1": CGSize(width: -21.46875, height: 10.30859375),
        "A2": CGSize(width: 1.6484375, height: 0.314453125),
        "ATTACK3": CGSize(width: 0, height: 0),
        "D1": CGSize(width: -11.462239583333314, height: 10.18359375),
        "D2": CGSize(width: 11.654947916666686, height: 0.314453125),
        "DECAY3": CGSize(width: -66, height: 113.4921875),
        "DELAY": CGSize(width: 10, height: 5.57421875),
        "ENV1_VCF": CGSize(width: 19.81640625, height: 9.39453125),
        "ENV1_WAVES": CGSize(width: -126, height: 205.1796875),
        "ENV2_LOUDNESS": CGSize(width: -60, height: 99.6953125),
        "ENV3_ATT": CGSize(width: -132, height: 223.7890625),
        "KF": CGSize(width: -0.244140625, height: 43.66796875),
        "KL": CGSize(width: -0.48828125, height: 84.3359375),
        "KW": CGSize(width: 0, height: 3),
        "MF": CGSize(width: -1.33984375, height: 112.52734375),
        "ML": CGSize(width: 3.43359375, height: -172.97265625),
        "MOD_WHL": CGSize(width: 6, height: 0.23828125),
        "MW": CGSize(width: 1.3125, height: 68.36328125),
        "R1": CGSize(width: 8.66796875, height: 10.79296875),
        "R2": CGSize(width: 31.66796875, height: 0.314453125),
        "RATE": CGSize(width: -122, height: 203.4609375),
        "S1": CGSize(width: -1.4557291666666288, height: 10.18359375),
        "S2": CGSize(width: 21.66145833333337, height: 0.314453125),
        "TF": CGSize(width: 0, height: 53.66796875),
        "TL": CGSize(width: 0, height: 94.3359375),
        "TM": CGSize(width: -0.97265625, height: -291.921875),
        "TW": CGSize(width: 0.8671875, height: 45.55078125),
        "VCF_CUTOFF": CGSize(width: -57.9765625, height: 4.51171875),
        "VCF_EMPHASIS": CGSize(width: -39.515625, height: 10.453125),
        "VF": CGSize(width: 1.43359375, height: 69.33203125),
        "VL": CGSize(width: -1.29296875, height: 115.93359375),
        "WAVESHAPE": CGSize(width: -56, height: 99.89453125),
        "WAVES_OSC": CGSize(width: 10.09765625, height: 13.9375),
        "WAVES_SUB": CGSize(width: 21.53125, height: 92.80078125),
    ]

    static let styles: [String: NudgeStyle] = [
        "BI": NudgeStyle(knobSize: 58),
        "DETU": NudgeStyle(knobSize: 58),
        "KF": NudgeStyle(knobSize: 58),
        "KL": NudgeStyle(knobSize: 58),
        "KW": NudgeStyle(knobSize: 58),
        "MF": NudgeStyle(knobSize: 58),
        "MW": NudgeStyle(knobSize: 58),
        "TF": NudgeStyle(knobSize: 58),
        "TL": NudgeStyle(knobSize: 58),
        "TW": NudgeStyle(knobSize: 58),
        "VCF_CUTOFF": NudgeStyle(knobSize: 80),
        "VCF_EMPHASIS": NudgeStyle(knobSize: 58),
        "VF": NudgeStyle(knobSize: 58),
        "VL": NudgeStyle(knobSize: 58),
        "WAVES_OSC": NudgeStyle(knobSize: 80),
        "WAVES_SUB": NudgeStyle(knobSize: 58),
    ]
}
