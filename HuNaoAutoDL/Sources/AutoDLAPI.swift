import Foundation

struct AutoDLAPI {
    private let token: String
    private let session: URLSession

    private static let baseURL = URL(string: "https://www.autodl.com/api/v1")!

    init(token: String) {
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func fetchInstances() async throws -> [AutoDLInstance] {
        let body: [String: Any] = [
            "date_from": "",
            "date_to": "",
            "page_index": 1,
            "page_size": 100,
            "status": [],
            "charge_type": []
        ]
        let json = try await post(path: "/instance", body: body)
        guard let data = json["data"] as? [String: Any],
              let rawList = data["list"] as? [[String: Any]]
        else {
            if let data = json["data"] as? [[String: Any]] {
                return data.compactMap(AutoDLInstance.parse)
            }
            throw AutoDLError.invalidResponse
        }
        return rawList.compactMap(AutoDLInstance.parse)
    }

    func fetchGPUStock(for instance: AutoDLInstance) async throws -> GPUStock {
        guard !instance.machineID.isEmpty else {
            return GPUStock(
                idleGPUs: 0,
                totalGPUs: nil,
                machineID: "",
                gpuName: instance.gpuName,
                requiredGPUs: instance.gpuCount,
                checkedAt: Date(),
                machineFound: false
            )
        }

        var body: [String: Any] = [
            "default_order": true,
            "gpu_idle_num": max(instance.gpuCount, 1),
            "page_index": 1,
            "page_size": 100
        ]
        if !instance.gpuName.isEmpty {
            body["gpu_type_name"] = [instance.gpuName]
        }
        if !instance.regionSign.isEmpty {
            body["region_sign_list"] = [instance.regionSign]
        }
        if !instance.chargeType.isEmpty {
            body["charge_type"] = instance.chargeType
        }

        let json = try await post(path: "/user/machine/list", body: body)
        let result = Self.parseMachineStock(json: json, targetMachineID: instance.machineID)
        return GPUStock(
            idleGPUs: result.idleGPUs,
            totalGPUs: result.totalGPUs,
            machineID: instance.machineID,
            gpuName: instance.gpuName,
            requiredGPUs: instance.gpuCount,
            checkedAt: Date(),
            machineFound: result.machineFound
        )
    }

    func powerOn(instanceUUID: String) async throws {
        let body: [String: Any] = [
            "instance_uuid": instanceUUID,
            "payload": "gpu"
        ]
        _ = try await post(path: "/instance/power_on", body: body)
    }

    func powerOff(instanceUUID: String) async throws {
        let body: [String: Any] = ["instance_uuid": instanceUUID]
        _ = try await post(path: "/instance/power_off", body: body)
    }

    func fetchBalance() async throws -> AccountBalance {
        let json = try await get(path: "/wallet")
        guard let data = json["data"] as? [String: Any] else {
            throw AutoDLError.invalidResponse
        }

        // AutoDL 钱包接口以千分之一元为单位返回金额。
        let cash = (jsonDouble(data["assets"]) ?? jsonDouble(data["balance"]) ?? 0) / 1000
        let blocked = (jsonDouble(data["blocked_asset"]) ?? jsonDouble(data["blocked_assets"]) ?? 0) / 1000
        let voucher = (jsonDouble(data["voucher_balance"]) ?? jsonDouble(data["voucher"]) ?? 0) / 1000
        return AccountBalance(
            cash: cash,
            blocked: blocked,
            voucher: voucher,
            paymentMethod: jsonString(data["payment_method"]),
            fetchedAt: Date()
        )
    }

    func fetchBills(from start: Date, to end: Date) async throws -> [BillRecord] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = AppTime.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let dateFrom = formatter.string(from: start)
        let dateTo = formatter.string(from: end)

        var records: [BillRecord] = []
        var seen = Set<String>()
        var page = 1
        // 每小时结算一条流水，30 天最多约 720 条，分页取完。
        while page <= 6 {
            let body: [String: Any] = [
                "order_uuid": "",
                "sub_name": "",
                "date_from": dateFrom,
                "date_to": dateTo,
                "page_index": page,
                "page_size": 500,
                "bill_type": ""
            ]
            let json = try await post(path: "/bill/list", body: body)
            guard let data = json["data"] as? [String: Any],
                  let list = data["list"] as? [[String: Any]]
            else { throw AutoDLError.invalidResponse }

            for item in list {
                if let record = BillRecord.parse(item), seen.insert(record.id).inserted {
                    records.append(record)
                }
            }

            let total = jsonInt(data["result_total"]) ?? records.count
            if list.isEmpty || records.count >= total { break }
            page += 1
        }
        return records
    }

    private func get(path: String) async throws -> [String: Any] {
        try await request(method: "GET", path: path, body: nil)
    }

    private func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        try await request(method: "POST", path: path, body: body)
    }

    private func request(
        method: String,
        path: String,
        body: [String: Any]?
    ) async throws -> [String: Any] {
        guard let url = URL(string: Self.baseURL.absoluteString + path) else {
            throw AutoDLError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("HuNaoAutoDL/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AutoDLError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AutoDLError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AutoDLError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AutoDLError.http(status: http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutoDLError.invalidResponse
        }

        let code = jsonString(json["code"]) ?? ""
        let message = jsonString(json["msg"]) ?? jsonString(json["message"]) ?? ""
        let success = code == "Success" || code == "success" || code == "0"
        guard success else {
            let error = AutoDLError.api(code: code, message: message)
            if error.isAuthFailure { throw AutoDLError.unauthorized }
            throw error
        }
        return json
    }

    private static func parseMachineStock(
        json: [String: Any],
        targetMachineID: String
    ) -> GPUStockParseResult {
        var machines: [[String: Any]] = []
        if let data = json["data"] as? [String: Any] {
            if let list = data["list"] as? [[String: Any]] {
                machines = list
            } else if let list = data["machines"] as? [[String: Any]] {
                machines = list
            } else {
                machines = [data]
            }
        } else if let list = json["data"] as? [[String: Any]] {
            machines = list
        }

        let normalizedTarget = targetMachineID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let target = machines.first { machine in
            let raw = jsonString(machine["machine_id"])
                ?? jsonString(machine["machine_uuid"])
                ?? jsonString(machine["id"])
                ?? ""
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTarget
        }

        guard let target else {
            return GPUStockParseResult(idleGPUs: 0, totalGPUs: nil, machineFound: false)
        }

        let idle = jsonInt(target["gpu_idle_num"])
            ?? jsonInt(target["idle_gpu_num"])
            ?? jsonInt(target["gpu_idle_count"])
            ?? 0
        let explicitTotal = jsonInt(target["gpu_all_num"])
            ?? jsonInt(target["gpu_total_num"])
            ?? jsonInt(target["total_gpu_num"])
        let possibleTotal = jsonInt(target["gpu_num"])
        let total = explicitTotal ?? possibleTotal.map { max($0, idle) }

        return GPUStockParseResult(
            idleGPUs: max(0, idle),
            totalGPUs: total,
            machineFound: true
        )
    }
}
