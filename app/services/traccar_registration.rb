# 관리자 화면과 시드가 공유하는 "Rails 레코드 + Traccar 자원" 등록 흐름의 공통 부모.
# 저장/삭제와 Traccar 동기화를 하나의 트랜잭션으로 묶어, 어느 한쪽이 실패하면 Rails 변경도 롤백한다
# ("Traccar 측 선행조건이 없으면 Rails 레코드도 존재할 수 없다"는 완전 롤백 정책).
#
# 서브클래스는 `manages 모델, with: Traccar서비스`로 대상을 선언한다. Traccar 서비스는
# call(record)/destroy(record)를 제공하는 TraccarApiClient 계열이어야 하며,
# 호출 방식이 다르면 sync/unsync를 재정의한다.
class TraccarRegistration
  Result = Struct.new(:record, :error, keyword_init: true) do
    def success? = error.nil?
    def failure? = !success?
  end

  class << self
    def manages(model_class, with: nil)
      @model_class = model_class
      @traccar_service = with
    end

    def create(attrs)
      persist(@model_class.new(attrs))
    end

    def update(record, attrs)
      record.assign_attributes(attrs)
      persist(record)
    end

    # DB 삭제를 먼저 시도한다. 이력(restrict_with_error) 때문에 거부되면 Traccar 자원은 건드리지 않는다.
    # Traccar 삭제가 실패하면 DB 삭제도 롤백된다.
    def destroy(record)
      transaction(record) do
        next error_of(record) unless record.destroy

        failure_message(unsync(record))
      end
    end

    private

    def persist(record)
      transaction(record) do
        next error_of(record) unless record.save

        failure_message(sync(record))
      end
    end

    # 블록이 오류 메시지(문자열)를 돌려주면 롤백하고, nil이면 커밋한다.
    def transaction(record)
      error = nil
      ActiveRecord::Base.transaction do
        error = yield
        raise ActiveRecord::Rollback if error
      end
      Result.new(record: record, error: error)
    end

    def sync(record)
      @traccar_service.call(record)
    end

    def unsync(record)
      @traccar_service.destroy(record)
    end

    def error_of(record)
      record.errors.full_messages.to_sentence
    end

    def failure_message(traccar_result)
      traccar_result.error if traccar_result.failure?
    end
  end
end
