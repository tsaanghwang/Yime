-- 假设业务表为 音元拼音 (id, 全拼, 干音, 映射编号, ...)
CREATE TRIGGER IF NOT EXISTS trg_enqueue_phoneme_mapping
AFTER INSERT ON "音元拼音"
FOR EACH ROW
BEGIN
  INSERT INTO mapping_queue(target_table, target_pk, hanzi, phoneme_key)
    VALUES ('音元拼音', NEW.编号, NEW.全拼, NEW.干音);
END;
