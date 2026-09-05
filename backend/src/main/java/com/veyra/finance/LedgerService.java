package com.veyra.finance;

import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Double-entry posting service -- the missing ledger layer flagged in the
 * repo audit (no ledger_accounts/ledger_transactions/ledger_entries existed
 * anywhere, despite the MVP spec's section 8/complement 63 requiring one).
 *
 * post() enforces the fundamental double-entry invariant in the service
 * layer (sum(DEBIT) == sum(CREDIT) per transaction) rather than only in a
 * SQL CHECK constraint -- a single-row CHECK can't express a cross-row
 * balance rule directly, and this fails loudly (ApiException) rather than
 * silently writing an unbalanced transaction if a future caller ever gets
 * the entries wrong.
 *
 * Only the 6 real, already-existing money-recognition events in this
 * codebase are wired to call this (see BookingController.complete(),
 * FinanceOpsController's settle/mark-paid endpoints) -- this service
 * itself is deliberately generic and event-agnostic; it doesn't know or
 * care what booking lifecycle event triggered a posting.
 */
@Service
public class LedgerService {
  private final JdbcTemplate db;

  public LedgerService(JdbcTemplate db) {
    this.db = db;
  }

  public record Entry(String accountCode, String direction, long amountMinor) {
    public static Entry debit(String accountCode, long amountMinor) {
      return new Entry(accountCode, "DEBIT", amountMinor);
    }

    public static Entry credit(String accountCode, long amountMinor) {
      return new Entry(accountCode, "CREDIT", amountMinor);
    }
  }

  @Transactional
  public UUID post(String eventType, UUID bookingId, String description, String currency, List<Entry> entries) {
    if (entries.isEmpty()) {
      throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "LEDGER_EMPTY_TRANSACTION");
    }

    long debits = entries.stream().filter(e -> "DEBIT".equals(e.direction())).mapToLong(Entry::amountMinor).sum();
    long credits = entries.stream().filter(e -> "CREDIT".equals(e.direction())).mapToLong(Entry::amountMinor).sum();
    if (debits != credits) {
      // Never silently post an unbalanced transaction -- this is the one
      // invariant that makes a ledger a ledger rather than just another
      // events table. A caller bug here must fail loudly, in the same
      // transaction, before anything is written.
      throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "LEDGER_UNBALANCED_TRANSACTION");
    }

    UUID transactionId = UUID.randomUUID();
    db.update(
        "insert into ledger_transactions(id,booking_id,event_type,description) values (?,?,?,?)",
        transactionId, bookingId, eventType, description);

    for (Entry entry : entries) {
      UUID accountId = accountIdFor(entry.accountCode());
      db.update(
          "insert into ledger_entries(transaction_id,account_id,direction,amount_minor,currency) values (?,?,?,?,?)",
          transactionId, accountId, entry.direction(), entry.amountMinor(), currency);
    }

    return transactionId;
  }

  private UUID accountIdFor(String code) {
    List<UUID> rows = db.queryForList("select id from ledger_accounts where code=?", UUID.class, code);
    if (rows.isEmpty()) {
      throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "LEDGER_UNKNOWN_ACCOUNT_" + code);
    }
    return rows.getFirst();
  }

  /** Trial balance: per-account net position (debits - credits for ASSET/EXPENSE accounts read as positive balance; for LIABILITY/REVENUE the natural balance is credit-positive, left to the caller/UI to interpret by account type rather than flipped here). */
  public List<Map<String, Object>> trialBalance() {
    return db.queryForList(
        "select a.code,a.name,a.type," +
            "coalesce(sum(case when e.direction='DEBIT' then e.amount_minor else 0 end),0) as total_debits_minor," +
            "coalesce(sum(case when e.direction='CREDIT' then e.amount_minor else 0 end),0) as total_credits_minor " +
            "from ledger_accounts a left join ledger_entries e on e.account_id=a.id " +
            "group by a.id,a.code,a.name,a.type order by a.code");
  }
}
