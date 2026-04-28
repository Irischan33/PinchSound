import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    
    let ballCount = 15
    let noteCount = 5
    
    let spiralTurns: Float = 2.0
    let spiralRadius: Float = 0.7
    let spiralBottomY: Float = 1.0
    let spiralTopY: Float = 2.0
    let clusterCenter: SIMD3<Float> = [0, 2.0, -2.2]
    let playerCenter: SIMD3<Float> = [0, 1.5, 0]
    
    let songNotes: [Int] = [1, 2, 3, 2, 1, 3, 5, 1]
    
    
    let mbiraTriggerCount = 3
    let bubbleAppearDelay: UInt64 = 5_000_000_000
    
    
    let correctNotesToTriggerPhase3 = 6
    
    
    let drawingPointCount = 15
    
    var body: some View {
        RealityView { content, attachments in
            
            // ===== 阶段 1：mbira =====
            await setupMbira(content: content, attachments: attachments)
            
            // 球团
            let clusterRoot = Entity()
            clusterRoot.name = "clusterRoot"
            clusterRoot.position = clusterCenter
            clusterRoot.isEnabled = false
            
            for i in 0..<ballCount {
                let ball = makeBall(index: i, total: ballCount)
                ball.position = clusterOffset(index: i, total: ballCount)
                clusterRoot.addChild(ball)
            }
            
            content.add(clusterRoot)
            
            
            await preloadAudioResources()
            
            state.clusterRoot = clusterRoot
            state.content = content
            
        } attachments: {
            
            Attachment(id: "mbiraHint") {
                Text("Pinch to explore the mbira")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            
            
            Attachment(id: "phase3Entry") {
                VStack(spacing: 12) {
                    Text("✨ Performance Mode ✨")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.white)
                    Text("Pinch to enter")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
        // drag
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handlePinch(on: value.entity)
                }
        )
        // drag2
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    if state.phase == .drawing {
                        handleDrawing(at: value.location3D, entity: value.entity)
                    }
                }
                .onEnded { _ in
                    if state.phase == .drawing {
                        handleDrawingPause()
                    }
                }
        )
    }
    
    @State private var state = SceneState()
    
    
    
    func setupMbira(content: RealityViewContent, attachments: RealityViewAttachments) async {
        guard let scene = try? await Entity(named: "Immersive", in: realityKitContentBundle) else {
            print("❌ 加载 Immersive 场景失败！")
            return
        }
        
        guard let mbira = scene.findEntity(named: "mbira") else {
            print("❌ 在场景里找不到名为 'mbira' 的 entity")
            return
        }
        
        let collisionBounds = mbira.visualBounds(relativeTo: mbira)
        mbira.components.set(CollisionComponent(
            shapes: [.generateBox(size: collisionBounds.extents)]
        ))
        mbira.components.set(InputTargetComponent())
        mbira.components.set(HoverEffectComponent())
        
        content.add(scene)
        state.mbira = mbira
        state.mbiraOriginalRotation = mbira.orientation
        
        
        if let hintPanel = attachments.entity(for: "mbiraHint") {
            hintPanel.position = [0, 0.25, 0]
            mbira.addChild(hintPanel)
            state.mbiraHintPanel = hintPanel
            print("✅ Hint panel 挂上了")
        } else {
            print("❌ Hint panel 没拿到")
        }
        
      
        if let phase3Panel = attachments.entity(for: "phase3Entry") {
            state.phase3EntryPanel = phase3Panel
            print("✅ Phase3 panel 准备好了")
        } else {
            print("❌ Phase3 panel 没拿到")
        }
        
        startMbiraFloating(mbira)
        
        print("✅ mbira 加载完成。请捏它 \(mbiraTriggerCount) 次")
    }
    
    func startMbiraFloating(_ mbira: Entity) {
        let baseY = mbira.position.y
        Task { @MainActor in
            let startTime = Date()
            while !Task.isCancelled {
                if state.phase != .intro && state.phase != .listening { break }
                let elapsed = Float(Date().timeIntervalSince(startTime))
                let offset = sin(elapsed * 2.0 * .pi / 4.0) * 0.02
                mbira.position.y = baseY + offset
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
    
    
    
    func preloadAudioResources() async {
        for i in 1...noteCount {
            let filename = "sound\(i)"
            do {
                let resource = try await AudioFileResource(named: "\(filename).mp3")
                state.audioResources.append(resource)
                print("✅ 加载音频：\(filename).mp3")
            } catch {
                print("❌ 加载音频失败：\(filename).mp3 — \(error)")
            }
        }
        
        do {
            let bg = try await AudioFileResource(
                named: "mbira_song.mp3",
                configuration: .init(shouldLoop: false)
            )
            state.backgroundMusic = bg
            print("✅ 加载背景音乐：mbira_song.mp3")
        } catch {
            print("❌ 加载背景音乐失败：\(error)")
        }
    }
    
    
    
    func handlePinch(on entity: Entity) {
        // 阶段 1：捏 mbira
        if state.phase == .intro && (entity.name == "mbira" || isPartOfMbira(entity)) {
            handleMbiraPinch()
            return
        }
        
        
        if entity.name == "bubble", state.phase == .listening {
            print("🫧 泡泡被捏！进入球飞模式")
            state.phase = .activated
            dismissBubble()
            
            state.mbiraHintPanel?.removeFromParent()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                fadeOutBackgroundMusic()
                showClusterAndStartReleasing()
            }
            return
        }
        
        
        if entity.name.hasPrefix("ball_"), state.phase == .performing {
            playBall(entity)
            return
        }
        
    
        if entity.name == "phase3EntryAnchor", state.phase == .performing {
            print("🎨 进入画画演奏模式！")
            enterDrawingMode()
            return
        }
        
        print("⚠️ 忽略捏合（entity=\(entity.name), phase=\(state.phase)）")
    }
    
    func isPartOfMbira(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while current != nil {
            if current?.name == "mbira" {
                return true
            }
            current = current?.parent
        }
        return false
    }
    
    
    
    func handleMbiraPinch() {
        guard let mbira = state.mbira else { return }
        guard !state.mbiraIsRotating else {
            print("⏳ mbira 还在旋转中，忽略此次 pinch")
            return
        }
        
        state.mbiraPinchCount += 1
        print("👌 捏 mbira 第 \(state.mbiraPinchCount) 次")
        
        
        rotateMbira120Degrees(mbira)
        
        if state.mbiraPinchCount >= mbiraTriggerCount {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // 等旋转完
                startBackgroundMusic()
            }
        }
    }
    
    func rotateMbira120Degrees(_ mbira: Entity) {
        state.mbiraIsRotating = true
        
        let currentRotation = mbira.orientation
        let increment = simd_quatf(angle: 2.0 * .pi / 3.0, axis: [0, 1, 0])  // 120°
        let targetRotation = currentRotation * increment
        
        
        Task { @MainActor in
            let duration: Double = 1.0
            let steps = 30
            let stepDuration: UInt64 = UInt64(duration / Double(steps) * 1_000_000_000)
            
            for step in 1...steps {
                let t = Float(step) / Float(steps)
                let easedT = t * t * (3 - 2 * t)  // smoothstep 缓动
                let interpolated = simd_slerp(currentRotation, targetRotation, easedT)
                mbira.orientation = interpolated
                try? await Task.sleep(nanoseconds: stepDuration)
            }
            
            mbira.orientation = targetRotation
            state.mbiraIsRotating = false
        }
    }
    
    
    
    func startBackgroundMusic() {
        guard let mbira = state.mbira else { return }
        guard let bg = state.backgroundMusic else {
            print("❌ 背景音乐未加载")
            return
        }
        
        print("🎵 开始播放背景音乐！")
        state.phase = .listening
        
        let playbackController = mbira.playAudio(bg)
        state.audioController = playbackController
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: bubbleAppearDelay)
            spawnBubble()
        }
    }
    
    
    
    func spawnBubble() {
        guard let content = state.content,
              let mbira = state.mbira else { return }
        
        print("🫧 泡泡出现")
        
        let bubbleMesh = MeshResource.generateSphere(radius: 0.04)
        var bubbleMat = PhysicallyBasedMaterial()
        let bubbleColor = UIColor(hue: 0.55, saturation: 0.4, brightness: 1.0, alpha: 1.0)
        bubbleMat.baseColor = .init(tint: bubbleColor.withAlphaComponent(0.3))
        bubbleMat.emissiveColor = .init(color: bubbleColor)
        bubbleMat.emissiveIntensity = 4.0
        bubbleMat.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        bubbleMat.roughness = .init(floatLiteral: 0.05)
        bubbleMat.clearcoat = .init(floatLiteral: 1.0)
        
        let bubble = ModelEntity(mesh: bubbleMesh, materials: [bubbleMat])
        bubble.name = "bubble"
        
        let mbiraWorldPos = mbira.position(relativeTo: nil)
        bubble.position = [mbiraWorldPos.x, mbiraWorldPos.y + 0.4, mbiraWorldPos.z]
        
        bubble.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.04)]))
        bubble.components.set(InputTargetComponent())
        bubble.components.set(HoverEffectComponent())
        
        bubble.scale = [0.01, 0.01, 0.01]
        content.add(bubble)
        state.bubble = bubble
        
        bubble.move(
            to: Transform(scale: [1.0, 1.0, 1.0], rotation: bubble.orientation, translation: bubble.position),
            relativeTo: bubble.parent,
            duration: 0.8,
            timingFunction: .easeOut
        )
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            startBubblePulse(bubble)
        }
    }
    
    func startBubblePulse(_ bubble: Entity) {
        Task { @MainActor in
            let startTime = Date()
            while !Task.isCancelled {
                if state.phase != .listening { break }
                let elapsed = Float(Date().timeIntervalSince(startTime))
                let scale = 1.0 + sin(elapsed * 2.0 * .pi / 2.0) * 0.15
                bubble.scale = SIMD3<Float>(repeating: scale)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
    
    func dismissBubble() {
        guard let bubble = state.bubble else { return }
        
        bubble.move(
            to: Transform(scale: [0.01, 0.01, 0.01], rotation: bubble.orientation, translation: bubble.position),
            relativeTo: bubble.parent,
            duration: 0.4,
            timingFunction: .easeIn
        )
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            bubble.removeFromParent()
            state.bubble = nil
        }
    }
    
    func fadeOutBackgroundMusic() {
        guard let controller = state.audioController else { return }
        controller.fade(to: .zero, duration: 1.5)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            controller.stop()
            state.audioController = nil
        }
    }
    
    
    
    func showClusterAndStartReleasing() {
        guard let cluster = state.clusterRoot else { return }
        cluster.isEnabled = true
        
        if let mbira = state.mbira {
            mbira.move(
                to: Transform(
                    scale: [0.001, 0.001, 0.001],
                    rotation: mbira.orientation,
                    translation: mbira.position
                ),
                relativeTo: mbira.parent,
                duration: 1.0,
                timingFunction: .easeIn
            )
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                mbira.isEnabled = false
            }
        }
        
        startRotation(entity: cluster)
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            startBallsRelease()
        }
    }
    
    
    
    func playBall(_ ball: Entity) {
        let ballIndex = Int(ball.name.replacingOccurrences(of: "ball_", with: "")) ?? 0
        let noteIndex = ballIndex % noteCount
        let noteNumber = noteIndex + 1
        
        let expectedNote = state.currentExpectedNote
        let isCorrect = (noteNumber == expectedNote)
        
        if !isCorrect {
            print("❌ 按错了！期望 sound\(expectedNote)，实际 sound\(noteNumber)")
            flashError(ball)
            return
        }
        
        print("✅ 按对！sound\(noteNumber)")
        
        if noteIndex < state.audioResources.count {
            let resource = state.audioResources[noteIndex]
            ball.playAudio(resource)
        }
        
        emitRipple(from: ball)
        flashHighlight(ball)
        clearHighlights()
        
        state.songProgress += 1
        state.totalCorrectCount += 1  // 🆕 累计捏对的总次数
        
    
        // 🆕 累计够 6 次 → 出现阶段 3 入口
        if state.totalCorrectCount >= correctNotesToTriggerPhase3 && !state.phase3EntryShown {
            state.phase3EntryShown = true
            spawnPhase3Entry()
        }
        
        if state.songProgress >= songNotes.count {
            print("🎉 弹完一遍！")
            songCompleted()
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                highlightNextNote()
            }
        }
    }
    
    func highlightNextNote() {
        guard state.songProgress < songNotes.count else { return }
        let expectedNote = songNotes[state.songProgress]
        state.currentExpectedNote = expectedNote
        print("👉 请按：sound\(expectedNote)")
        
        for ball in state.spiralBalls {
            guard let model = ball as? ModelEntity else { continue }
            let ballIndex = Int(ball.name.replacingOccurrences(of: "ball_", with: "")) ?? 0
            let noteNumber = (ballIndex % noteCount) + 1
            
            if noteNumber == expectedNote {
                startHighlightAnimation(model)
            }
        }
    }
    
    func startHighlightAnimation(_ ball: ModelEntity) {
        let ballName = ball.name
        state.highlightedBalls.insert(ballName)
        
        Task { @MainActor in
            let startTime = Date()
            while !Task.isCancelled {
                if !state.highlightedBalls.contains(ballName) { break }
                let elapsed = Float(Date().timeIntervalSince(startTime))
                let pulse = 6.0 + sin(elapsed * 2.0 * .pi / 1.0) * 2.0
                
                if var mat = ball.model?.materials.first as? PhysicallyBasedMaterial {
                    mat.emissiveIntensity = pulse
                    ball.model?.materials = [mat]
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            
            if var mat = ball.model?.materials.first as? PhysicallyBasedMaterial {
                mat.emissiveIntensity = 1.5
                ball.model?.materials = [mat]
            }
        }
    }
    
    func clearHighlights() {
        state.highlightedBalls.removeAll()
    }
    
    func flashError(_ ball: Entity) {
        guard let model = ball as? ModelEntity else { return }
        guard var mat = model.model?.materials.first as? PhysicallyBasedMaterial else { return }
        
        let originalColor = colorOfBall(ball)
        mat.emissiveColor = .init(color: UIColor.red)
        mat.emissiveIntensity = 5.0
        model.model?.materials = [mat]
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if var restored = model.model?.materials.first as? PhysicallyBasedMaterial {
                restored.emissiveColor = .init(color: originalColor)
                restored.emissiveIntensity = 1.5
                model.model?.materials = [restored]
            }
        }
    }
    
    func songCompleted() {
        for ball in state.spiralBalls {
            guard let model = ball as? ModelEntity else { continue }
            flashHighlight(model)
            emitRipple(from: model)
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            state.songProgress = 0
            print("🔄 重置，可以再弹一遍")
            highlightNextNote()
        }
    }
    
    
    
    func spawnPhase3Entry() {
        guard let content = state.content else { return }
        print("✨ 阶段 3 入口出现！")
        
        
        let anchor = Entity()
        anchor.name = "phase3EntryAnchor"
        anchor.position = [0, 1.6, -1.0]
        
        anchor.components.set(CollisionComponent(shapes: [.generateBox(size: [0.5, 0.3, 0.05])]))
        anchor.components.set(InputTargetComponent())
        anchor.components.set(HoverEffectComponent())
        
        content.add(anchor)
        state.phase3EntryAnchor = anchor
        
        
        if let panel = state.phase3EntryPanel {
            anchor.addChild(panel)
            print("✅ Panel 挂上 anchor 了")
        } else {
            print("❌ phase3EntryPanel 是 nil，attachments 没准备好")
        }
    }
    
    
    
    func enterDrawingMode() {
        state.phase = .drawing
        
        
        state.phase3EntryAnchor?.removeFromParent()
        state.phase3EntryAnchor = nil
        
       
        if let cluster = state.clusterRoot {
            cluster.move(
                to: Transform(
                    scale: [0.01, 0.01, 0.01],
                    rotation: cluster.orientation,
                    translation: cluster.position
                ),
                relativeTo: cluster.parent,
                duration: 1.0,
                timingFunction: .easeIn
            )
        }
        
        // 让所有阶段 2 的球消失
        for ball in state.spiralBalls {
            ball.move(
                to: Transform(
                    scale: [0.01, 0.01, 0.01],
                    rotation: ball.orientation,
                    translation: ball.position
                ),
                relativeTo: ball.parent,
                duration: 1.0,
                timingFunction: .easeIn
            )
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            
            // 移除球
            for ball in state.spiralBalls {
                ball.removeFromParent()
            }
            state.spiralBalls = []
            state.clusterRoot?.removeFromParent()
            
            // 让 mbira 重新出现
            if let mbira = state.mbira {
                mbira.isEnabled = true
                mbira.scale = [0.001, 0.001, 0.001]
                // 用 RCP 里设置的原始 scale
                let targetScale = SIMD3<Float>(repeating: 0.001)  // 占位，等下立刻改
                
                mbira.move(
                    to: Transform(
                        scale: targetScale * 1000,  // 恢复到一个合理大小
                        rotation: state.mbiraOriginalRotation,
                        translation: mbira.position
                    ),
                    relativeTo: mbira.parent,
                    duration: 1.5,
                    timingFunction: .easeOut
                )
            }
            
            // 1.5 秒后生成画画路径点
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            spawnDrawingPath()
        }
    }
    
    // MARK: - 🎨 生成画画路径（15 个点的曲线）
    
    func spawnDrawingPath() {
        guard let content = state.content else { return }
        guard let mbira = state.mbira else { return }
        
        print("🎨 生成画画路径")
        
        let mbiraPos = mbira.position(relativeTo: nil)
        // 路径中心：mbira 前方 50cm
        let pathCenter = SIMD3<Float>(mbiraPos.x, mbiraPos.y, mbiraPos.z + 0.5)
        
        for i in 0..<drawingPointCount {
            let t = Float(i) / Float(drawingPointCount - 1)
            
            // 波浪线：水平铺开 60cm，上下波动 ±10cm
            let x = (t - 0.5) * 0.6
            let y = sin(t * 2 * .pi * 2) * 0.1  // 2 个波峰
            let z: Float = 0
            
            let pointPos = pathCenter + SIMD3<Float>(x, y, z)
            
            let point = makeDrawingPoint(index: i)
            point.position = pointPos
            content.add(point)
            state.drawingPoints.append(point)
        }
        
        // 创建画笔
        let brush = makeBrush()
        brush.position = pathCenter
        content.add(brush)
        state.brush = brush
        state.brushBaseY = pathCenter.y
        
        print("✅ 画画路径准备完成，开始捏住手画")
    }
    
    func makeDrawingPoint(index: Int) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.025)
        var material = PhysicallyBasedMaterial()
        // 未画：白色发光
        material.baseColor = .init(tint: UIColor.white.withAlphaComponent(0.4))
        material.emissiveColor = .init(color: .white)
        material.emissiveIntensity = 2.0
        material.blending = .transparent(opacity: .init(floatLiteral: 0.6))
        material.roughness = .init(floatLiteral: 0.1)
        material.clearcoat = .init(floatLiteral: 1.0)
        
        let point = ModelEntity(mesh: mesh, materials: [material])
        point.name = "drawpoint_\(index)"
        point.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.05)]))
        point.components.set(InputTargetComponent())
        point.components.set(HoverEffectComponent())
        return point
    }
    
    func makeBrush() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.02)
        var material = PhysicallyBasedMaterial()
        let warmColor = UIColor(hue: 0.1, saturation: 0.5, brightness: 1.0, alpha: 1.0)
        material.baseColor = .init(tint: warmColor.withAlphaComponent(0.6))
        material.emissiveColor = .init(color: warmColor)
        material.emissiveIntensity = 6.0
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        
        let brush = ModelEntity(mesh: mesh, materials: [material])
        brush.name = "brush"
        brush.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.02)]))
        brush.components.set(InputTargetComponent())
        return brush
    }
    
    
    
    func handleDrawing(at location: Point3D, entity: Entity) {
        guard let brush = state.brush else { return }
        
        // 把 SwiftUI 的 3D 坐标转成 RealityKit 坐标（米为单位）
        let pos = SIMD3<Float>(Float(location.x), Float(location.y), Float(location.z))
        brush.position = pos
        
        // 重置"停止"计时器
        state.lastDrawTime = Date()
        state.drawingPaused = false
        
        // 如果音乐正在暂停，恢复
        if let controller = state.audioController, controller.isPlaying == false && state.drawingProgress > 0 && state.drawingProgress < state.drawingPoints.count {
            // 不主动 resume，避免重复 — 在用户画到下一个点时会自动推进
        }
        
        // 检查是否画到了某个未画过的点
        for (i, point) in state.drawingPoints.enumerated() {
            if state.paintedPoints.contains(i) { continue }  // 已经画过
            if i != state.drawingProgress { continue }  // 必须按顺序画下一个点
            
            let distance = simd_distance(brush.position, point.position)
            if distance < 0.06 {  // 6cm 范围内算"画到了"
                paintPoint(at: i)
                break
            }
        }
    }
    
    func paintPoint(at index: Int) {
        guard let point = state.drawingPoints[safe: index] as? ModelEntity else { return }
        
        print("🎨 画到第 \(index + 1) / \(drawingPointCount) 个点")
        state.paintedPoints.insert(index)
        state.drawingProgress = index + 1
        
        // 点变色（白 → 暖橙）
        if var mat = point.model?.materials.first as? PhysicallyBasedMaterial {
            let warmColor = UIColor(hue: 0.08, saturation: 0.85, brightness: 1.0, alpha: 1.0)
            mat.baseColor = .init(tint: warmColor)
            mat.emissiveColor = .init(color: warmColor)
            mat.emissiveIntensity = 4.0
            point.model?.materials = [mat]
        }
        
        // 推进 mp3：根据 progress 计算应该播到哪
        advanceMusicToProgress()
        
        // 全部画完
        if state.drawingProgress >= drawingPointCount {
            print("🎉 画画演奏完成！")
            drawingCompleted()
        }
    }
    
    func advanceMusicToProgress() {
        guard let mbira = state.mbira else { return }
        guard let bg = state.backgroundMusic else { return }
        
        // 第一次画时，启动音乐
        if state.audioController == nil || state.audioController?.isPlaying == false {
            let controller = mbira.playAudio(bg)
            state.audioController = controller
            print("▶️ 开始/恢复播放")
        }
    }
    
    // MARK: - 🎨 画停下来的处理
    
    func handleDrawingPause() {
        state.lastDrawTime = Date()
        // 启动一个计时检查任务
        startPauseTimer()
    }
    
    func startPauseTimer() {
        // 防止启动多个计时
        if state.pauseTimerRunning { return }
        state.pauseTimerRunning = true
        
        Task { @MainActor in
            while state.phase == .drawing {
                try? await Task.sleep(nanoseconds: 200_000_000)  // 每 0.2s 检查一次
                
                guard let lastTime = state.lastDrawTime else { continue }
                let elapsed = Date().timeIntervalSince(lastTime)
                
                // 1 秒不画 → 暂停音乐
                if elapsed > 1.0 && !state.drawingPaused {
                    state.drawingPaused = true
                    print("⏸️ 暂停音乐")
                    state.audioController?.pause()
                }
                
                // 5 秒不画 → 重置一切
                if elapsed > 5.0 {
                    print("🔄 5 秒未画，重置进度")
                    resetDrawing()
                    state.pauseTimerRunning = false
                    return
                }
            }
            state.pauseTimerRunning = false
        }
    }
    
    func resetDrawing() {
        // 停止音乐
        state.audioController?.stop()
        state.audioController = nil
        
        // 重置所有点
        for (i, point) in state.drawingPoints.enumerated() {
            guard let model = point as? ModelEntity else { continue }
            if var mat = model.model?.materials.first as? PhysicallyBasedMaterial {
                mat.baseColor = .init(tint: UIColor.white.withAlphaComponent(0.4))
                mat.emissiveColor = .init(color: .white)
                mat.emissiveIntensity = 2.0
                model.model?.materials = [mat]
            }
        }
        
        state.paintedPoints.removeAll()
        state.drawingProgress = 0
        state.drawingPaused = false
        state.lastDrawTime = nil
    }
    
    func drawingCompleted() {
        print("🎉 演奏完成")
        // 所有点欢呼一下
        for point in state.drawingPoints {
            guard let model = point as? ModelEntity else { continue }
            emitRipple(from: model)
            flashHighlight(model)
        }
    }
    
    // MARK: - 涟漪 & 高光
    
    func emitRipple(from ball: Entity) {
        guard let content = state.content else { return }
        let ballColor = colorOfBall(ball)
        
        let rippleMesh = MeshResource.generateSphere(radius: 0.04)
        var rippleMaterial = PhysicallyBasedMaterial()
        rippleMaterial.baseColor = .init(tint: ballColor.withAlphaComponent(0.0))
        rippleMaterial.emissiveColor = .init(color: ballColor)
        rippleMaterial.emissiveIntensity = 4.0
        rippleMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.6))
        rippleMaterial.roughness = .init(floatLiteral: 0.5)
        
        let ripple = ModelEntity(mesh: rippleMesh, materials: [rippleMaterial])
        ripple.position = ball.position(relativeTo: nil)
        content.add(ripple)
        
        ripple.move(
            to: Transform(scale: [6.0, 6.0, 6.0], rotation: ripple.orientation, translation: ripple.position),
            relativeTo: nil,
            duration: 0.6,
            timingFunction: .easeOut
        )
        
        Task { @MainActor in
            let steps = 20
            for step in 0..<steps {
                try? await Task.sleep(nanoseconds: 30_000_000)
                let t = Float(step) / Float(steps)
                if var mat = ripple.model?.materials.first as? PhysicallyBasedMaterial {
                    mat.emissiveIntensity = 4.0 * (1.0 - t)
                    mat.blending = .transparent(opacity: .init(floatLiteral: 0.6 * (1.0 - t)))
                    ripple.model?.materials = [mat]
                }
            }
            ripple.removeFromParent()
        }
    }
    
    func flashHighlight(_ ball: Entity) {
        guard let model = ball as? ModelEntity else { return }
        guard var material = model.model?.materials.first as? PhysicallyBasedMaterial else { return }
        
        let originalIntensity: Float = 1.5
        let peakIntensity: Float = 6.0
        material.emissiveIntensity = peakIntensity
        model.model?.materials = [material]
        
        Task { @MainActor in
            let steps = 15
            for step in 0..<steps {
                try? await Task.sleep(nanoseconds: 25_000_000)
                let t = Float(step) / Float(steps)
                if var mat = model.model?.materials.first as? PhysicallyBasedMaterial {
                    mat.emissiveIntensity = peakIntensity - (peakIntensity - originalIntensity) * t
                    model.model?.materials = [mat]
                }
            }
        }
    }
    
    func colorOfBall(_ ball: Entity) -> UIColor {
        if ball.name.hasPrefix("ball_") {
            let idx = Int(ball.name.replacingOccurrences(of: "ball_", with: "")) ?? 0
            return warmGradientColor(index: idx, total: ballCount)
        }
        return UIColor(hue: 0.1, saturation: 0.7, brightness: 1.0, alpha: 1.0)
    }
    
    // MARK: - 球脱落
    
    func startBallsRelease() {
        guard let clusterRoot = state.clusterRoot,
              let content = state.content else { return }
        
        let balls = clusterRoot.children
            .filter { $0.name.hasPrefix("ball_") }
            .sorted { (a, b) -> Bool in
                let aIdx = Int(a.name.replacingOccurrences(of: "ball_", with: "")) ?? 0
                let bIdx = Int(b.name.replacingOccurrences(of: "ball_", with: "")) ?? 0
                return aIdx < bIdx
            }
        
        state.spiralBalls = Array(balls)
        
        for (i, ball) in balls.enumerated() {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(i) * 200_000_000)
                releaseBall(ball, toSpiralIndex: i, total: balls.count, content: content)
            }
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(balls.count) * 200_000_000 + 2_200_000_000)
            enterPerformanceMode()
        }
    }
    
    func enterPerformanceMode() {
        print("🎼 进入演奏阶段！自动开始教学模式")
        state.phase = .performing
        
        for ball in state.spiralBalls {
            guard let model = ball as? ModelEntity else { continue }
            model.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.04)]))
            model.components.set(InputTargetComponent())
            model.components.set(HoverEffectComponent())
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            highlightNextNote()
        }
    }
    
    func releaseBall(_ ball: Entity, toSpiralIndex i: Int, total: Int, content: RealityViewContent) {
        let currentWorldPos = ball.position(relativeTo: nil)
        ball.removeFromParent()
        ball.setPosition(currentWorldPos, relativeTo: nil)
        content.add(ball)
        
        let targetPos = spiralPosition(index: i, total: total)
        let midPoint = midCurvePoint(from: currentWorldPos, to: targetPos)
        
        ball.move(
            to: Transform(scale: ball.scale, rotation: ball.orientation, translation: midPoint),
            relativeTo: nil,
            duration: 1.2,
            timingFunction: .easeOut
        )
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            ball.move(
                to: Transform(scale: ball.scale, rotation: ball.orientation, translation: targetPos),
                relativeTo: nil,
                duration: 1.0,
                timingFunction: .easeInOut
            )
        }
    }
    
    func spiralPosition(index: Int, total: Int) -> SIMD3<Float> {
        let t = Float(index) / Float(total - 1)
        let angle = t * spiralTurns * 2 * .pi
        let y = spiralBottomY + t * (spiralTopY - spiralBottomY)
        let x = playerCenter.x + cos(angle) * spiralRadius
        let z = playerCenter.z + sin(angle) * spiralRadius
        return [x, y, z]
    }
    
    func midCurvePoint(from start: SIMD3<Float>, to end: SIMD3<Float>) -> SIMD3<Float> {
        let mid = (start + end) * 0.5
        return [mid.x, mid.y + 0.3, mid.z]
    }
    
    func startRotation(entity: Entity) {
        Task { @MainActor in
            let startTime = Date()
            while !Task.isCancelled {
                if state.phase == .performing || state.phase == .drawing { break }
                let elapsed = Float(Date().timeIntervalSince(startTime))
                let angle = elapsed * (.pi * 2 / 20)
                let tilt = simd_quatf(angle: .pi / 12, axis: [0, 0, 1])
                let spin = simd_quatf(angle: angle, axis: [0, 1, 0])
                entity.orientation = tilt * spin
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
    
    func makeBall(index: Int, total: Int) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.045)
        let color = warmGradientColor(index: index, total: total)
        
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.withAlphaComponent(0.5))
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 1.5
        material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        material.roughness = .init(floatLiteral: 0.05)
        material.metallic = .init(floatLiteral: 0.1)
        material.clearcoat = .init(floatLiteral: 1.0)
        material.clearcoatRoughness = .init(floatLiteral: 0.05)
        
        let ball = ModelEntity(mesh: mesh, materials: [material])
        ball.name = "ball_\(index)"
        return ball
    }
    
    func warmGradientColor(index: Int, total: Int) -> UIColor {
        let t = Float(index) / Float(total - 1)
        let hue = CGFloat(0.13 - 0.13 * t)
        return UIColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: 1.0)
    }
    
    func clusterOffset(index: Int, total: Int) -> SIMD3<Float> {
        let goldenAngle = Float.pi * (3.0 - sqrt(5.0))
        let i = Float(index)
        let n = Float(total)
        let y = 1.0 - (i / (n - 1)) * 2.0
        let radiusAtY = sqrt(1.0 - y * y)
        let theta = goldenAngle * i
        let x = cos(theta) * radiusAtY
        let z = sin(theta) * radiusAtY
        let clusterRadius: Float = 0.08
        return SIMD3<Float>(x, y, z) * clusterRadius
    }
}

enum ScenePhase {
    case intro
    case listening
    case activated
    case performing
    case drawing  // 🆕 阶段 3
}

@Observable
class SceneState {
    var phase: ScenePhase = .intro
    var clusterRoot: Entity?
    var content: RealityViewContent?
    var audioResources: [AudioFileResource] = []
    var spiralBalls: [Entity] = []
    
    // 教学模式
    var songProgress: Int = 0
    var currentExpectedNote: Int = -1
    var highlightedBalls: Set<String> = []
    var totalCorrectCount: Int = 0  // 🆕 累计捏对总数
    
    // 阶段 1
    var mbira: Entity?
    var mbiraOriginalRotation: simd_quatf = simd_quatf()
    var mbiraPinchCount: Int = 0
    var mbiraIsRotating: Bool = false
    var mbiraHintPanel: Entity?
    var backgroundMusic: AudioFileResource?
    var audioController: AudioPlaybackController?
    var bubble: Entity?
    
    // 🆕 阶段 3 入口
    var phase3EntryPanel: Entity?
    var phase3EntryAnchor: Entity?
    var phase3EntryPanelExists: Bool = false
    var phase3EntryShown: Bool = false  // 🆕 是否已经显示过阶段 3 入口
    
    // 🆕 阶段 3：画画
    var drawingPoints: [Entity] = []
    var paintedPoints: Set<Int> = []
    var drawingProgress: Int = 0
    var brush: Entity?
    var brushBaseY: Float = 0
    var lastDrawTime: Date?
    var drawingPaused: Bool = false
    var pauseTimerRunning: Bool = false
}

// MARK: - 数组安全下标扩展

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
}
