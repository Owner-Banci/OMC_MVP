import SwiftUI
import Combine

// MARK: - Models
struct Appointment: Identifiable, Hashable, Decodable {
    let id: UUID
    let period: String
    let type: String
    let title: String
    let patientName: String
    let room: String
    let date: String
    let startTime: String
    let endTime: String
    let hasConflict: Bool
    let patientInfo: String
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isCurrentUser: Bool
}


final class WebSocketWorker: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    @Published var messages: [ChatMessage] = []

    let chatID: String = "chat123"
    let currentUserID: String = "currentUser"
    let remoteUserID: String = "remoteUser"

    func connect() {
        guard let url = URL(string: "ws://127.0.0.1:8000/ws") else { return }
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    func sendMessage(_ message: String) {
        let outgoing = ChatMessage(text: message, isCurrentUser: true)
        messages.append(outgoing)

        let msg = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(msg) { error in
            if let error = error {
                print("Ошибка отправки: \(error)")
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(.string(let text)):
                let incoming = ChatMessage(text: text, isCurrentUser: false)
                DispatchQueue.main.async {
                    self.messages.append(incoming)
                }
            case .failure(let error):
                print("Ошибка получения: \(error)")
            default:
                break
            }
            self.receiveMessage()
        }
    }
}

// MARK: - ViewModels
final class ScheduleViewModel: ObservableObject {
    @Published var appointments: [Appointment] = []

    init() {
        loadAppointmentsFromJSON()
    }

    private func loadAppointmentsFromJSON() {
        guard let url = Bundle.main.url(forResource: "appointments", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Appointment].self, from: data) else {
            print("Ошибка загрузки appointments.json")
            return
        }
        appointments = decoded
    }
}

// MARK: - Views
struct ContentView: View {
    @StateObject private var viewModel = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("ПОНЕДЕЛЬНИК, 19 МАЯ").font(.caption)) {
                    ForEach(viewModel.appointments) { appointment in
                        NavigationLink(value: appointment) {
                            AppointmentRow(appointment: appointment)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Расписание")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Appointment.self) { appointment in
                AppointmentDetailView(appointment: appointment)
            }
        }
    }
}

struct AppointmentRow: View {
    let appointment: Appointment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 32, height: 32)
                Text(appointment.period)
                    .font(.subheadline).bold()
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.type)
                    .font(.caption).foregroundColor(.secondary)
                Text(appointment.title)
                    .font(.body).bold()
                    .foregroundColor(.primary)
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String(appointment.patientName.prefix(1)))
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                    Text(appointment.patientName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(appointment.room)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if appointment.hasConflict {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.caption2)
                        Text("Несколько приёмов в это время")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(appointment.startTime)-\(appointment.endTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AppointmentDetailView: View {
    let appointment: Appointment
    @State private var showChat = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appointment.type)
                .font(.caption).foregroundColor(.blue)
            Text(appointment.title)
                .font(.title2).bold()
            HStack(spacing: 16) {
                Label("\(appointment.startTime)-\(appointment.endTime)", systemImage: "clock")
                Label(appointment.room, systemImage: "location.fill")
            }
            Divider()
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(appointment.patientName.prefix(1)))
                            .font(.title3)
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(appointment.patientName)
                        .font(.headline)
                    Text("Пациент")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            Divider()
            Text("Информация о пациенте")
                .font(.subheadline).foregroundColor(.secondary)
            Text(appointment.patientInfo)
                .font(.body)
            Spacer()

            Button("Написать") {
                showChat = true
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .padding(.top)
        }
        .padding()
        .navigationTitle("\(appointment.period) приём")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showChat) {
            ChatScreen()
        }
    }
}

struct ChatScreen: View {
    @StateObject private var chatWorker = WebSocketWorker()
    @State private var newMessage: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Чат с пациентом")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(chatWorker.messages) { msg in
                            messageBubble(msg.text, isCurrentUser: msg.isCurrentUser)
                                .id(msg.id)
                        }
                    }
                    .onChange(of: chatWorker.messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(chatWorker.messages.last?.id, anchor: .bottom)
                        }
                    }
                }
            }

            HStack {
                TextField("Сообщение...", text: $newMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Отправить") {
                    guard !newMessage.isEmpty else { return }
                    chatWorker.sendMessage(newMessage)
                    newMessage = ""
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear { chatWorker.connect() }
        .onDisappear { chatWorker.disconnect() }
    }

    func messageBubble(_ text: String, isCurrentUser: Bool) -> some View {
        HStack {
            if !isCurrentUser { Spacer() }
            Text(text)
                .padding(8)
                .background(isCurrentUser ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(isCurrentUser ? .white : .black)
                .cornerRadius(10)
            if isCurrentUser { Spacer() }
        }
        .padding(.horizontal)
    }
}

// MARK: - Preview
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
