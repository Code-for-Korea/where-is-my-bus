require "csv"

# 지역 CSV를 읽어 새 코드만 추가한다. 이미 있는 코드는 고치지 않고 원본과 다른 필드만 보고한다.
# 수만 행을 다루므로 검증은 전부 메모리에서 하고, 삽입은 레벨별 배치로 한다.
class RegionImporter
  HEADER = %w[code parent_code level kind name south west north east].freeze
  BOUNDS = %w[south west north east].freeze
  BATCH_SIZE = 1000
  MAX_ERRORS = 100
  DECIMAL = /\A-?\d+(\.\d+)?\z/

  Result = Struct.new(:added, :unchanged, :differences, :errors, keyword_init: true) do
    def success? = errors.empty?
  end

  def self.call(path)
    new(path).call
  end

  def initialize(path)
    @path = path.to_s
    @errors = []
  end

  def call
    rows = read_rows
    return failure if rows.nil? || @errors.any?

    existing = Region.pluck(:code, :id, :level, :name, :kind, :parent_id, :south, :west, :north, :east)
                     .index_by(&:first)
    validate(rows, existing)
    return failure if @errors.any?

    new_rows, known_rows = rows.partition { |row| !existing.key?(row[:code]) }
    differences = compare(known_rows, existing)
    insert(new_rows, existing)

    Result.new(added: new_rows.size, unchanged: known_rows.size - differences.map { |d| d[:code] }.uniq.size,
               differences: differences, errors: [])
  end

  private

  def failure
    errors = @errors.first(MAX_ERRORS)
    errors << "…외 #{@errors.size - MAX_ERRORS}건" if @errors.size > MAX_ERRORS
    Result.new(added: 0, unchanged: 0, differences: [], errors: errors)
  end

  def read_rows
    rows = []
    File.open(@path, "r:bom|utf-8") do |file|
      csv = CSV.new(file)
      header = csv.shift&.map { |value| value.to_s.strip }
      unless header == HEADER
        @errors << "헤더가 올바르지 않습니다 (필요: #{HEADER.join(',')})"
        return nil
      end

      csv.each do |values|
        next if values.empty?

        rows << HEADER.zip(values.map { |value| value.to_s.strip }).to_h.symbolize_keys.merge(line: csv.lineno)
      end
    end
    rows
  rescue SystemCallError, IOError, EncodingError, CSV::MalformedCSVError => e
    @errors << "파일을 읽을 수 없습니다: #{@path} (#{e.message})"
    nil
  end

  def validate(rows, existing)
    first_line = {}
    in_file = {}
    rows.each do |row|
      if row[:code].blank?
        @errors << "#{row[:line]}행: 코드가 비어 있습니다"
      elsif first_line.key?(row[:code])
        @errors << "#{row[:line]}행: 코드 #{row[:code]}이(가) #{first_line[row[:code]]}행과 중복됩니다"
      else
        first_line[row[:code]] = row[:line]
        in_file[row[:code]] = row
      end
    end

    rows.each do |row|
      next if row[:code].blank? || existing.key?(row[:code]) || first_line[row[:code]] != row[:line]

      validate_row(row, existing, in_file)
    end
  end

  def validate_row(row, existing, in_file)
    line = row[:line]
    @errors << "#{line}행: 종류가 비어 있습니다" if row[:kind].blank?
    @errors << "#{line}행: 이름이 비어 있습니다" if row[:name].blank?
    level = integer_level(row[:level])
    @errors << "#{line}행: 레벨은 1 이상의 정수여야 합니다" if level.nil?
    validate_bounds(row)
    validate_parent(row, level, existing, in_file) if row[:parent_code].present?
  end

  def integer_level(value)
    level = Integer(value, 10, exception: false)
    level if level && level >= 1
  end

  def validate_bounds(row)
    line = row[:line]
    values = BOUNDS.map { |key| row[key.to_sym] }
    return if values.all?(&:blank?)

    if values.any?(&:blank?)
      @errors << "#{line}행: 영역(남·서·북·동)은 모두 입력하거나 모두 비워야 합니다"
    elsif values.any? { |value| !DECIMAL.match?(value) }
      @errors << "#{line}행: 영역 값이 숫자가 아닙니다"
    else
      south, west, north, east = values.map { |value| BigDecimal(value) }
      @errors << "#{line}행: 위도는 -90~90 범위여야 합니다" unless [ south, north ].all? { |v| v.between?(-90, 90) }
      @errors << "#{line}행: 경도는 -180~180 범위여야 합니다" unless [ west, east ].all? { |v| v.between?(-180, 180) }
      @errors << "#{line}행: 남쪽이 북쪽보다 클 수 없습니다" if south > north
      @errors << "#{line}행: 서쪽이 동쪽보다 클 수 없습니다" if west > east
    end
  end

  def validate_parent(row, level, existing, in_file)
    parent_level = existing[row[:parent_code]]&.at(2) || integer_level(in_file[row[:parent_code]]&.fetch(:level))
    if existing[row[:parent_code]].nil? && in_file[row[:parent_code]].nil?
      @errors << "#{row[:line]}행: 상위 지역 코드 #{row[:parent_code]}를 찾을 수 없습니다"
    elsif level && parent_level && parent_level >= level
      @errors << "#{row[:line]}행: 상위 지역의 레벨(#{parent_level})이 이 지역의 레벨(#{level})보다 낮아야 합니다"
    end
  end

  # 이미 있는 코드는 건드리지 않고 원본과 다른 필드만 모은다.
  def compare(known_rows, existing)
    code_by_id = existing.values.to_h { |record| [ record[1], record[0] ] }
    known_rows.flat_map do |row|
      _code, _id, level, name, kind, parent_id, *bounds = existing.fetch(row[:code])
      diffs = []
      diffs << { code: row[:code], field: :name, db: name, source: row[:name] } if name != row[:name]
      diffs << { code: row[:code], field: :level, db: level, source: row[:level].to_i } if level != row[:level].to_i
      diffs << { code: row[:code], field: :kind, db: kind, source: row[:kind] } if kind != row[:kind]
      db_parent = code_by_id[parent_id]
      diffs << { code: row[:code], field: :parent, db: db_parent, source: row[:parent_code].presence } if db_parent != row[:parent_code].presence
      BOUNDS.zip(bounds).each do |key, db_value|
        source = row[key.to_sym].presence
        next if same_bound?(db_value, source)

        diffs << { code: row[:code], field: key.to_sym, db: db_value && format("%.6f", db_value), source: source }
      end
      diffs
    end
  end

  def same_bound?(db_value, source)
    return db_value.nil? && source.nil? if db_value.nil? || source.nil?

    BigDecimal(db_value.to_s).round(6) == BigDecimal(source).round(6)
  end

  def insert(new_rows, existing)
    return if new_rows.empty?

    ids = existing.transform_values { |record| record[1] }
    Region.transaction do
      new_rows.group_by { |row| row[:level].to_i }.sort.each do |_level, level_rows|
        level_rows.each_slice(BATCH_SIZE) do |batch|
          Region.insert_all(batch.map { |row| attributes_for(row, ids) })
          ids.merge!(Region.where(code: batch.map { |row| row[:code] }).pluck(:code, :id).to_h)
        end
      end
    end
  end

  def attributes_for(row, ids)
    { code: row[:code], parent_id: row[:parent_code].present? ? ids.fetch(row[:parent_code]) : nil,
      level: row[:level].to_i, kind: row[:kind], name: row[:name],
      south: row[:south].presence, west: row[:west].presence, north: row[:north].presence, east: row[:east].presence }
  end
end
