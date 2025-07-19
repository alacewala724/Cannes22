import SwiftUI

struct CountryCode {
    let name: String
    let code: String
    let flag: String
    let placeholder: String
    
    static let popular = [
        CountryCode(name: "United States", code: "+1", flag: "🇺🇸", placeholder: "(555) 123-4567"),
        CountryCode(name: "Canada", code: "+1", flag: "🇨🇦", placeholder: "(555) 123-4567"),
        CountryCode(name: "United Kingdom", code: "+44", flag: "🇬🇧", placeholder: "7911 123456"),
        CountryCode(name: "Germany", code: "+49", flag: "🇩🇪", placeholder: "1512 3456789"),
        CountryCode(name: "France", code: "+33", flag: "🇫🇷", placeholder: "6 12 34 56 78"),
        CountryCode(name: "Spain", code: "+34", flag: "🇪🇸", placeholder: "612 34 56 78"),
        CountryCode(name: "Italy", code: "+39", flag: "🇮🇹", placeholder: "312 345 6789"),
        CountryCode(name: "Australia", code: "+61", flag: "🇦🇺", placeholder: "412 345 678"),
        CountryCode(name: "India", code: "+91", flag: "🇮🇳", placeholder: "98765 43210"),
        CountryCode(name: "Japan", code: "+81", flag: "🇯🇵", placeholder: "90 1234 5678"),
        CountryCode(name: "South Korea", code: "+82", flag: "🇰🇷", placeholder: "10 1234 5678"),
        CountryCode(name: "Brazil", code: "+55", flag: "🇧🇷", placeholder: "11 91234-5678"),
        CountryCode(name: "Mexico", code: "+52", flag: "🇲🇽", placeholder: "55 1234 5678"),
        CountryCode(name: "China", code: "+86", flag: "🇨🇳", placeholder: "138 0013 8000")
    ]
    
    static let all = [
        CountryCode(name: "Afghanistan", code: "+93", flag: "🇦🇫", placeholder: "70 123 4567"),
        CountryCode(name: "Albania", code: "+355", flag: "🇦🇱", placeholder: "67 212 3456"),
        CountryCode(name: "Algeria", code: "+213", flag: "🇩🇿", placeholder: "551 23 45 67"),
        CountryCode(name: "Argentina", code: "+54", flag: "🇦🇷", placeholder: "11 1234-5678"),
        CountryCode(name: "Australia", code: "+61", flag: "🇦🇺", placeholder: "412 345 678"),
        CountryCode(name: "Austria", code: "+43", flag: "🇦🇹", placeholder: "664 123456"),
        CountryCode(name: "Bangladesh", code: "+880", flag: "🇧🇩", placeholder: "1812-345678"),
        CountryCode(name: "Belgium", code: "+32", flag: "🇧🇪", placeholder: "470 12 34 56"),
        CountryCode(name: "Brazil", code: "+55", flag: "🇧🇷", placeholder: "11 91234-5678"),
        CountryCode(name: "Canada", code: "+1", flag: "🇨🇦", placeholder: "(555) 123-4567"),
        CountryCode(name: "Chile", code: "+56", flag: "🇨🇱", placeholder: "9 1234 5678"),
        CountryCode(name: "China", code: "+86", flag: "🇨🇳", placeholder: "138 0013 8000"),
        CountryCode(name: "Colombia", code: "+57", flag: "🇨🇴", placeholder: "321 1234567"),
        CountryCode(name: "Egypt", code: "+20", flag: "🇪🇬", placeholder: "100 123 4567"),
        CountryCode(name: "France", code: "+33", flag: "🇫🇷", placeholder: "6 12 34 56 78"),
        CountryCode(name: "Germany", code: "+49", flag: "🇩🇪", placeholder: "1512 3456789"),
        CountryCode(name: "India", code: "+91", flag: "🇮🇳", placeholder: "98765 43210"),
        CountryCode(name: "Indonesia", code: "+62", flag: "🇮🇩", placeholder: "812-345-678"),
        CountryCode(name: "Italy", code: "+39", flag: "🇮🇹", placeholder: "312 345 6789"),
        CountryCode(name: "Japan", code: "+81", flag: "🇯🇵", placeholder: "90 1234 5678"),
        CountryCode(name: "Mexico", code: "+52", flag: "🇲🇽", placeholder: "55 1234 5678"),
        CountryCode(name: "Netherlands", code: "+31", flag: "🇳🇱", placeholder: "6 12345678"),
        CountryCode(name: "Nigeria", code: "+234", flag: "🇳🇬", placeholder: "802 123 4567"),
        CountryCode(name: "Pakistan", code: "+92", flag: "🇵🇰", placeholder: "301 2345678"),
        CountryCode(name: "Philippines", code: "+63", flag: "🇵🇭", placeholder: "917 123 4567"),
        CountryCode(name: "Poland", code: "+48", flag: "🇵🇱", placeholder: "512 345 678"),
        CountryCode(name: "Russia", code: "+7", flag: "🇷🇺", placeholder: "912 345-67-89"),
        CountryCode(name: "Saudi Arabia", code: "+966", flag: "🇸🇦", placeholder: "50 123 4567"),
        CountryCode(name: "South Africa", code: "+27", flag: "🇿🇦", placeholder: "82 123 4567"),
        CountryCode(name: "South Korea", code: "+82", flag: "🇰🇷", placeholder: "10 1234 5678"),
        CountryCode(name: "Spain", code: "+34", flag: "🇪🇸", placeholder: "612 34 56 78"),
        CountryCode(name: "Thailand", code: "+66", flag: "🇹🇭", placeholder: "81 234 5678"),
        CountryCode(name: "Turkey", code: "+90", flag: "🇹🇷", placeholder: "532 123 45 67"),
        CountryCode(name: "Ukraine", code: "+380", flag: "🇺🇦", placeholder: "50 123 4567"),
        CountryCode(name: "United Arab Emirates", code: "+971", flag: "🇦🇪", placeholder: "50 123 4567"),
        CountryCode(name: "United Kingdom", code: "+44", flag: "🇬🇧", placeholder: "7911 123456"),
        CountryCode(name: "United States", code: "+1", flag: "🇺🇸", placeholder: "(555) 123-4567"),
        CountryCode(name: "Vietnam", code: "+84", flag: "🇻🇳", placeholder: "912 345 678")
    ]
}

struct CountryCodePicker: View {
    @Binding var selectedCountry: CountryCode
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    let showAllCountries: Bool
    
    init(selectedCountry: Binding<CountryCode>, showAllCountries: Bool = true) {
        self._selectedCountry = selectedCountry
        self.showAllCountries = showAllCountries
    }
    
    var filteredCountries: [CountryCode] {
        let countries = showAllCountries ? CountryCode.all : CountryCode.popular
        
        if searchText.isEmpty {
            if showAllCountries {
                return CountryCode.popular + CountryCode.all.filter { country in
                    !CountryCode.popular.contains { $0.code == country.code && $0.name == country.name }
                }
            } else {
                return CountryCode.popular
            }
        } else {
            return countries.filter { country in
                country.name.localizedCaseInsensitiveContains(searchText) ||
                country.code.contains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                if searchText.isEmpty && showAllCountries {
                    Section("Popular") {
                        ForEach(CountryCode.popular, id: \.code) { country in
                            CountryRow(country: country, selectedCountry: $selectedCountry)
                        }
                    }
                    
                    Section("All Countries") {
                        ForEach(CountryCode.all.filter { country in
                            !CountryCode.popular.contains { $0.code == country.code && $0.name == country.name }
                        }, id: \.code) { country in
                            CountryRow(country: country, selectedCountry: $selectedCountry)
                        }
                    }
                } else {
                    let sectionTitle = showAllCountries ? "Countries" : "Popular Countries"
                    Section(sectionTitle) {
                        ForEach(filteredCountries, id: \.code) { country in
                            CountryRow(country: country, selectedCountry: $selectedCountry)
                        }
                    }
                }
            }
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search countries")
        }
    }
}

struct CountryRow: View {
    let country: CountryCode
    @Binding var selectedCountry: CountryCode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Button(action: {
            selectedCountry = country
            dismiss()
        }) {
            HStack {
                Text(country.flag)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(country.name)
                        .foregroundColor(.primary)
                    Text(country.code)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if selectedCountry.code == country.code && selectedCountry.name == country.name {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
} 