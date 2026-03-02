//
//  RichTextAccessoryView.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//


import UIKit

// MARK: - RichTextAccessoryView

final class RichTextAccessoryView: UIInputView {
    
    var onCommand: ((RichTextCommand) -> Void)?
    var onDismiss: (() -> Void)?
    
    // ── Layout ────────────────────────────────────────────────────────────
    private let baseBar      = UIView()
    private let expandedBar  = UIView()
    private var expandedBarHeight: NSLayoutConstraint!
    private var isExpanded = false
    
    private let baseHeight: CGFloat     = 44
    private let expandedHeight: CGFloat = 200
    
    // ── Init ─────────────────────────────────────────────────────────────
    init(onCommand: @escaping (RichTextCommand) -> Void,
         onDismiss: @escaping () -> Void) {
        self.onCommand = onCommand
        self.onDismiss = onDismiss
        super.init(frame: .zero, inputViewStyle: .keyboard)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    // MARK: - Build UI
    
    private func buildUI() {
        backgroundColor = .systemBackground.withAlphaComponent(0)
        
        // ── Separator ─────────────────────────────────────────────────────
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = UIColor.separator
        
        // ── expanded bar ──────────────────────────────────────────────────
        expandedBar.translatesAutoresizingMaskIntoConstraints = false
        expandedBar.backgroundColor = UIColor.systemBackground
        expandedBar.alpha = 0
        buildExpandedBar()
        
        // ── base bar ──────────────────────────────────────────────────────
        baseBar.translatesAutoresizingMaskIntoConstraints = false
        baseBar.backgroundColor = .clear
        buildBaseBar()
        
        addSubview(sep)
        addSubview(expandedBar)
        addSubview(baseBar)
        
        expandedBarHeight = expandedBar.heightAnchor.constraint(equalToConstant: 0)
        
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.heightAnchor.constraint(equalToConstant: 0.33),
            
            expandedBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            expandedBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            expandedBar.topAnchor.constraint(equalTo: sep.bottomAnchor),
            expandedBarHeight,
            
            baseBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            baseBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            baseBar.topAnchor.constraint(equalTo: expandedBar.bottomAnchor),
            baseBar.heightAnchor.constraint(equalToConstant: baseHeight)
        ])
    }
    
    // MARK: - Base bar
    
    private func buildBaseBar() {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis      = .horizontal
        stack.spacing   = 2
        stack.alignment = .center
        
        // Aa → toggle expanded
        let aaBtn = toolbarButton(title: "Aa", fontSize: 15, weight: .medium)
        aaBtn.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        stack.addArrangedSubview(aaBtn)
        
        stack.addArrangedSubview(makeSeparator())
        
        // Bold
        let boldBtn = toolbarButton(sfSymbol: nil, title: "B", fontSize: 17, weight: .bold)
        boldBtn.addTarget(self, action: #selector(tapBold), for: .touchUpInside)
        stack.addArrangedSubview(boldBtn)
        
        // Italic
        let italicBtn = toolbarButton(title: "I", fontSize: 17, weight: .regular)
        italicBtn.titleLabel?.font = UIFont.italicSystemFont(ofSize: 17)
        italicBtn.addTarget(self, action: #selector(tapItalic), for: .touchUpInside)
        stack.addArrangedSubview(italicBtn)
        
        // Underline
        let uBtn = toolbarButton(sfSymbol: "underline")
        uBtn.addTarget(self, action: #selector(tapUnderline), for: .touchUpInside)
        stack.addArrangedSubview(uBtn)
        
        // Strikethrough
        let sBtn = toolbarButton(sfSymbol: "strikethrough")
        sBtn.addTarget(self, action: #selector(tapStrikethrough), for: .touchUpInside)
        stack.addArrangedSubview(sBtn)
        
        stack.addArrangedSubview(makeSeparator())
        
        // Checklist
        let checkBtn = toolbarButton(sfSymbol: "checklist")
        checkBtn.addTarget(self, action: #selector(tapChecklist), for: .touchUpInside)
        stack.addArrangedSubview(checkBtn)
        
        stack.addArrangedSubview(UIView()) // spacer
        
        // Dismiss keyboard
        let kbBtn = toolbarButton(sfSymbol: "keyboard.chevron.compact.down")
        kbBtn.addTarget(self, action: #selector(tapDismiss), for: .touchUpInside)
        stack.addArrangedSubview(kbBtn)
        
        baseBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: baseBar.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: baseBar.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: baseBar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: baseBar.bottomAnchor)
        ])
    }
    
    // MARK: - Expanded bar (Apple Notes "Formato")
    
    private func buildExpandedBar() {
        
        // ── Row 1: style chips ────────────────────────────────────────────
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        
        let chipStack = UIStackView()
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        chipStack.axis    = .horizontal
        chipStack.spacing = 10
        
        let styles: [(String, UIFont)] = [
            ("Corpo",       .preferredFont(forTextStyle: .body)),
            ("Titolo",      .systemFont(ofSize: 20, weight: .bold)),
            ("Intestazione",.systemFont(ofSize: 17, weight: .semibold)),
            ("Sottoint.",   .systemFont(ofSize: 14, weight: .semibold)),
            ("Mono",        .monospacedSystemFont(ofSize: 14, weight: .regular))
        ]
        let _: [RichTextCommand] = [.body, .h1, .h2, .h2, .body] // map to available cmds
        
        for (i, (label, font)) in styles.enumerated() {
            let chip = makeChip(label: label, font: font, tag: i)
            chip.addTarget(self, action: #selector(tapStyleChip(_:)), for: .touchUpInside)
            chipStack.addArrangedSubview(chip)
        }
        
        scrollView.addSubview(chipStack)
        NSLayoutConstraint.activate([
            chipStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            chipStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            chipStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            chipStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            chipStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        
        // ── Separator ─────────────────────────────────────────────────────
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = .separator
        
        // ── Row 2: inline formatting + quote ─────────────────────────────
        let row2 = UIStackView()
        row2.translatesAutoresizingMaskIntoConstraints = false
        row2.axis = .horizontal; row2.spacing = 8
        
        let bBtn2 = fmtButton(title: "B", font: .systemFont(ofSize: 17, weight: .bold))
        bBtn2.addTarget(self, action: #selector(tapBold), for: .touchUpInside)
        let iBtn2 = fmtButton(title: "I", font: .italicSystemFont(ofSize: 17))
        iBtn2.addTarget(self, action: #selector(tapItalic), for: .touchUpInside)
        let uBtn2 = fmtButton(sfSymbol: "underline")
        uBtn2.addTarget(self, action: #selector(tapUnderline), for: .touchUpInside)
        let sBtn2 = fmtButton(sfSymbol: "strikethrough")
        sBtn2.addTarget(self, action: #selector(tapStrikethrough), for: .touchUpInside)
        let spacer2 = UIView(); spacer2.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let qBtn = fmtButton(sfSymbol: "text.quote")
        qBtn.addTarget(self, action: #selector(tapQuote), for: .touchUpInside)
        
        for v in [bBtn2, iBtn2, uBtn2, sBtn2, spacer2, qBtn] { row2.addArrangedSubview(v) }
        
        // ── Row 3: lists + indent ─────────────────────────────────────────
        let row3 = UIStackView()
        row3.translatesAutoresizingMaskIntoConstraints = false
        row3.axis = .horizontal; row3.spacing = 8
        
        let blBtn  = fmtButton(sfSymbol: "list.bullet")
        blBtn.addTarget(self, action: #selector(tapBullet), for: .touchUpInside)
        let nlBtn  = fmtButton(sfSymbol: "list.number")
        nlBtn.addTarget(self, action: #selector(tapNumber), for: .touchUpInside)
        let chkBtn = fmtButton(sfSymbol: "checklist")
        chkBtn.addTarget(self, action: #selector(tapChecklist), for: .touchUpInside)
        let spacer3 = UIView(); spacer3.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let deBtn  = fmtButton(sfSymbol: "decrease.indent")
        deBtn.addTarget(self, action: #selector(tapIndentLess), for: .touchUpInside)
        let inBtn  = fmtButton(sfSymbol: "increase.indent")
        inBtn.addTarget(self, action: #selector(tapIndentMore), for: .touchUpInside)
        
        for v in [blBtn, nlBtn, chkBtn, spacer3, deBtn, inBtn] { row3.addArrangedSubview(v) }
        
        // ── Assemble ──────────────────────────────────────────────────────
        let vStack = UIStackView(arrangedSubviews: [scrollView, sep, row2, row3])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis      = .vertical
        vStack.spacing   = 10
        vStack.alignment = .fill
        
        expandedBar.addSubview(vStack)
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 44),
            sep.heightAnchor.constraint(equalToConstant: 0.33),
            row2.heightAnchor.constraint(equalToConstant: 40),
            row3.heightAnchor.constraint(equalToConstant: 40),
            
            vStack.leadingAnchor.constraint(equalTo: expandedBar.leadingAnchor, constant: 12),
            vStack.trailingAnchor.constraint(equalTo: expandedBar.trailingAnchor, constant: -12),
            vStack.topAnchor.constraint(equalTo: expandedBar.topAnchor, constant: 12),
            vStack.bottomAnchor.constraint(lessThanOrEqualTo: expandedBar.bottomAnchor, constant: -8)
        ])
    }
    
    // MARK: - Expand / Collapse
    
    @objc private func toggleExpanded() {
        isExpanded.toggle()
        let targetHeight: CGFloat = isExpanded ? expandedHeight : 0
        let targetAlpha:  CGFloat = isExpanded ? 1 : 0
        
        UIView.animate(withDuration: 0.28,
                       delay: 0,
                       usingSpringWithDamping: 0.82,
                       initialSpringVelocity: 0,
                       options: .curveEaseInOut) {
            self.expandedBarHeight.constant = targetHeight
            self.expandedBar.alpha = targetAlpha
            // Ask the system to re-layout the inputAccessoryView
            self.superview?.setNeedsLayout()
            self.superview?.layoutIfNeeded()
        }
    }
    
    // ── Collapse when keyboard is dismissed ───────────────────────────────
    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        expandedBarHeight.constant = 0
        expandedBar.alpha = 0
    }
    
    // MARK: - Actions
    
    @objc private func tapDismiss() { collapse(); onDismiss?() }
    @objc private func tapBold()          { onCommand?(.bold) }
    @objc private func tapItalic()        { onCommand?(.italic) }
    @objc private func tapUnderline()     { onCommand?(.underline) }
    @objc private func tapStrikethrough() { onCommand?(.strikethrough) }
    @objc private func tapBullet()        { onCommand?(.bullet) }
    @objc private func tapNumber()        { onCommand?(.number) }
    @objc private func tapChecklist() {
        // Checklist = bullet list con simbolo spuntabile (usiamo .bullet come approssimazione)
        onCommand?(.bullet)
    }
    @objc private func tapQuote()       { onCommand?(.quote) }
    @objc private func tapIndentMore()  { onCommand?(.indentMore) }
    @objc private func tapIndentLess()  { onCommand?(.indentLess) }
    
    @objc private func tapStyleChip(_ sender: UIButton) {
        switch sender.tag {
        case 0: onCommand?(.body)
        case 1: onCommand?(.h1)
        case 2: onCommand?(.h2)
        case 3: onCommand?(.h2) // subheading
        default: onCommand?(.body)
        }
    }
    
    // MARK: - UIKit helpers
    
    private func toolbarButton(sfSymbol: String? = nil,
                               title: String? = nil,
                               fontSize: CGFloat = 16,
                               weight: UIFont.Weight = .regular) -> UIButton {
        let btn = UIButton(type: .system)
        btn.tintColor = .label
        if let symbol = sfSymbol {
            btn.setImage(UIImage(systemName: symbol,
                                 withConfiguration: UIImage.SymbolConfiguration(
                                    pointSize: fontSize, weight: weight == .bold ? .bold : .regular
                                 )), for: .normal)
        } else if let t = title {
            btn.setTitle(t, for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: fontSize, weight: weight)
            btn.setTitleColor(.label, for: .normal)
        }
        btn.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return btn
    }
    
    private func fmtButton(sfSymbol: String? = nil,
                           title: String? = nil,
                           font: UIFont = .systemFont(ofSize: 16)) -> UIButton {
        let btn = UIButton(type: .system)
        btn.tintColor = .label
        btn.backgroundColor = UIColor.secondarySystemBackground
        btn.layer.cornerRadius = 10
        btn.clipsToBounds = true
        if let symbol = sfSymbol {
            btn.setImage(UIImage(systemName: symbol,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)),
                         for: .normal)
        } else if let t = title {
            btn.setTitle(t, for: .normal)
            btn.titleLabel?.font = font
            btn.setTitleColor(.label, for: .normal)
        }
        btn.widthAnchor.constraint(equalToConstant: 46).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return btn
    }
    
    private func makeChip(label: String, font: UIFont, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.tag = tag
        btn.setTitle(label, for: .normal)
        btn.titleLabel?.font = font
        btn.setTitleColor(.label, for: .normal)
        btn.backgroundColor = UIColor.secondarySystemBackground
        btn.layer.cornerRadius = 10
        btn.clipsToBounds = true
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        return btn
    }
    
    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return v
    }
    
    // MARK: - intrinsicContentSize
    
    override var intrinsicContentSize: CGSize {
        let h = baseHeight + (isExpanded ? expandedHeight : 0)
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }
}
